#!/bin/bash

# Constants
SERVICE="sender-backend.service"
UNIT_FILE="/lib/systemd/system/$SERVICE"
IMAGE="ghcr.io/upri-earthquake/sender-backend:latest"
CONTAINER="sender-backend"
VOLUME="UPRI-volume"
DOCKER_NETWORK="UPRI-docker-network"
UPDATE_SERVICE="sender-backend-update.service"
UPDATE_TIMER="sender-backend-update.timer"
UPDATE_SERVICE_FILE="/lib/systemd/system/$UPDATE_SERVICE"
UPDATE_TIMER_FILE="/lib/systemd/system/$UPDATE_TIMER"

# Optional DNS overrides for container resolution:
# - SENDER_BACKEND_DNS: comma/space-separated DNS servers (e.g., "10.0.0.2,10.0.0.3")
# - SENDER_BACKEND_DNS_FILE: file with DNS servers (one per line, or resolv.conf-style nameserver lines)
# - SENDER_BACKEND_DNS_CHECK_HOSTS: comma/space-separated probe hosts for DNS self-check
# - SENDER_BACKEND_DNS_CHECK_TIMEOUT_SEC: per-host DNS probe timeout in seconds (default: 8)

DNS_MODE_LABEL_KEY="upri.sender-backend.dns-mode"
DNS_CHECK_HOSTS_DEFAULT="earthquake.science.upd.edu.ph github.com"
DNS_FLAGS=()

function get_docker_create_network_flag() {
    if docker create --help 2>/dev/null | grep -q -- '--network'; then
        printf "%s" "--network"
    else
        printf "%s" "--net"
    fi
}

function trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf "%s" "$value"
}

function is_valid_ipv4() {
    local ip="$1"
    local octet

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
    for octet in "$o1" "$o2" "$o3" "$o4"; do
        ((octet >= 0 && octet <= 255)) || return 1
    done
    return 0
}

function is_valid_ipv6() {
    local ip="$1"

    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" =~ ^[0-9A-Fa-f:.]+$ ]] || return 1
    [[ "$ip" != *:::* ]] || return 1
    return 0
}

function is_valid_dns_server_ip() {
    local dns_server="$1"

    if is_valid_ipv4 "$dns_server"; then
        return 0
    fi
    if is_valid_ipv6 "$dns_server"; then
        return 0
    fi
    return 1
}

function is_disallowed_dns_server_ip() {
    local dns_server="$1"
    local dns_server_lc="${dns_server,,}"

    if [[ "$dns_server" == "0.0.0.0" ]] || [[ "$dns_server" =~ ^127\. ]]; then
        return 0
    fi

    if [[ "$dns_server_lc" == "::" ]] || [[ "$dns_server_lc" == "::1" ]]; then
        return 0
    fi

    if [[ "$dns_server_lc" == fe80:* ]]; then
        return 0
    fi

    return 1
}

function extract_dns_servers_from_file() {
    local dns_file="$1"

    awk '
        /^[[:space:]]*($|#)/ {next}
        /^[[:space:]]*nameserver[[:space:]]+/ {print $2; next}
        /^[[:space:]]*(search|domain|options|sortlist)[[:space:]]+/ {next}
        {
            gsub(/,/, " ");
            for (i = 1; i <= NF; i++) print $i;
        }
    ' "$dns_file"
}

function collect_explicit_dns_servers() {
    local dns_override="${SENDER_BACKEND_DNS:-}"
    local dns_override_file="${SENDER_BACKEND_DNS_FILE:-}"
    local dns_server
    local existing_server
    local duplicate
    local -a dns_servers=()

    if [[ -n "$dns_override" && -n "$dns_override_file" ]]; then
        echo -en "[\e[1;33mWARN\e[0m] " >&2
        echo "Both SENDER_BACKEND_DNS and SENDER_BACKEND_DNS_FILE are set. Using SENDER_BACKEND_DNS." >&2
    fi

    if [[ -n "$dns_override" ]]; then
        dns_override="${dns_override//,/ }"
        for dns_server in $dns_override; do
            dns_server="$(trim_whitespace "$dns_server")"
            [[ -z "$dns_server" ]] && continue

            if ! is_valid_dns_server_ip "$dns_server"; then
                echo -en "[\e[1;33mWARN\e[0m] " >&2
                echo "Ignoring invalid DNS server in SENDER_BACKEND_DNS: $dns_server" >&2
                continue
            fi

            if is_disallowed_dns_server_ip "$dns_server"; then
                echo -en "[\e[1;33mWARN\e[0m] " >&2
                echo "Ignoring non-routable DNS server in SENDER_BACKEND_DNS: $dns_server" >&2
                continue
            fi

            duplicate=0
            for existing_server in "${dns_servers[@]}"; do
                if [[ "$existing_server" == "$dns_server" ]]; then
                    duplicate=1
                    break
                fi
            done
            [[ $duplicate -eq 1 ]] && continue
            dns_servers+=("$dns_server")
        done
    elif [[ -n "$dns_override_file" ]]; then
        if [[ ! -r "$dns_override_file" ]]; then
            echo -en "[\e[1;33mWARN\e[0m] " >&2
            echo "DNS override file $dns_override_file is not readable." >&2
            return 0
        fi

        while IFS= read -r dns_server; do
            dns_server="$(trim_whitespace "$dns_server")"
            [[ -z "$dns_server" ]] && continue

            if ! is_valid_dns_server_ip "$dns_server"; then
                echo -en "[\e[1;33mWARN\e[0m] " >&2
                echo "Ignoring invalid DNS server in $dns_override_file: $dns_server" >&2
                continue
            fi

            if is_disallowed_dns_server_ip "$dns_server"; then
                echo -en "[\e[1;33mWARN\e[0m] " >&2
                echo "Ignoring non-routable DNS server in $dns_override_file: $dns_server" >&2
                continue
            fi

            duplicate=0
            for existing_server in "${dns_servers[@]}"; do
                if [[ "$existing_server" == "$dns_server" ]]; then
                    duplicate=1
                    break
                fi
            done
            [[ $duplicate -eq 1 ]] && continue
            dns_servers+=("$dns_server")
        done < <(extract_dns_servers_from_file "$dns_override_file")
    fi

    for dns_server in "${dns_servers[@]}"; do
        printf "%s\n" "$dns_server"
    done
}

function collect_host_policy_dns_servers() {
    local dns_server
    local existing_server
    local duplicate
    local dns_file
    local -a dns_servers=()
    local -a dns_files=("/etc/resolv.conf")

    if [[ -r "/run/systemd/resolve/resolv.conf" ]]; then
        dns_files+=("/run/systemd/resolve/resolv.conf")
    fi

    for dns_file in "${dns_files[@]}"; do
        [[ -r "$dns_file" ]] || continue
        while IFS= read -r dns_server; do
            dns_server="$(trim_whitespace "$dns_server")"
            [[ -z "$dns_server" ]] && continue

            if ! is_valid_dns_server_ip "$dns_server"; then
                continue
            fi

            if is_disallowed_dns_server_ip "$dns_server"; then
                continue
            fi

            duplicate=0
            for existing_server in "${dns_servers[@]}"; do
                if [[ "$existing_server" == "$dns_server" ]]; then
                    duplicate=1
                    break
                fi
            done
            [[ $duplicate -eq 1 ]] && continue
            dns_servers+=("$dns_server")
        done < <(extract_dns_servers_from_file "$dns_file")
    done

    for dns_server in "${dns_servers[@]}"; do
        printf "%s\n" "$dns_server"
    done
}

function prepare_dns_flags() {
    local dns_mode="${1:-auto}"
    local dns_server
    local -a dns_servers=()
    local dns_source="docker-default"

    DNS_FLAGS=()

    case "$dns_mode" in
        auto)
            while IFS= read -r dns_server; do
                [[ -z "$dns_server" ]] && continue
                dns_servers+=("$dns_server")
            done < <(collect_explicit_dns_servers)

            if [[ ${#dns_servers[@]} -gt 0 ]]; then
                dns_source="explicit"
            fi
            ;;
        host-policy)
            while IFS= read -r dns_server; do
                [[ -z "$dns_server" ]] && continue
                dns_servers+=("$dns_server")
            done < <(collect_host_policy_dns_servers)

            if [[ ${#dns_servers[@]} -eq 0 ]]; then
                echo -en "[\e[1;31mFAILED\e[0m] "
                echo "No valid host-policy DNS resolvers found in /etc/resolv.conf or /run/systemd/resolve/resolv.conf."
                return 1
            fi
            dns_source="host-policy"
            ;;
        *)
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Unsupported DNS mode: $dns_mode"
            return 1
            ;;
    esac

    for dns_server in "${dns_servers[@]}"; do
        DNS_FLAGS+=(--dns "$dns_server")
    done

    if [[ "$dns_source" == "explicit" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Using explicit DNS override servers: ${dns_servers[*]}"
    elif [[ "$dns_source" == "host-policy" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Using host-policy DNS fallback servers: ${dns_servers[*]}"
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Using Docker default DNS forwarding (no explicit --dns overrides)."
    fi

    return 0
}

function get_container_dns_mode() {
    local dns_mode
    dns_mode="$(docker inspect --format "{{ index .Config.Labels \"$DNS_MODE_LABEL_KEY\" }}" "$CONTAINER" 2>/dev/null)"

    if [[ -z "$dns_mode" || "$dns_mode" == "<no value>" ]]; then
        dns_mode="auto"
    fi

    printf "%s" "$dns_mode"
}

function run_container_dns_probe() {
    local dns_host="$1"
    local timeout_sec="${SENDER_BACKEND_DNS_CHECK_TIMEOUT_SEC:-8}"
    local node_probe="const dns=require('dns');const host=process.argv[1];dns.lookup(host,(err)=>process.exit(err?1:0));"

    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_sec" docker exec "$CONTAINER" node -e "$node_probe" "$dns_host" >/dev/null 2>&1 && return 0
        timeout "$timeout_sec" docker exec "$CONTAINER" getent hosts "$dns_host" >/dev/null 2>&1 && return 0
        timeout "$timeout_sec" docker exec "$CONTAINER" nslookup "$dns_host" >/dev/null 2>&1 && return 0
        timeout "$timeout_sec" docker exec "$CONTAINER" host "$dns_host" >/dev/null 2>&1 && return 0
    else
        docker exec "$CONTAINER" node -e "$node_probe" "$dns_host" >/dev/null 2>&1 && return 0
        docker exec "$CONTAINER" getent hosts "$dns_host" >/dev/null 2>&1 && return 0
        docker exec "$CONTAINER" nslookup "$dns_host" >/dev/null 2>&1 && return 0
        docker exec "$CONTAINER" host "$dns_host" >/dev/null 2>&1 && return 0
    fi

    return 1
}

function check_container_dns_resolution() {
    local dns_check_hosts="${SENDER_BACKEND_DNS_CHECK_HOSTS:-$DNS_CHECK_HOSTS_DEFAULT}"
    local dns_host

    dns_check_hosts="${dns_check_hosts//,/ }"
    if [[ -z "${dns_check_hosts//[[:space:]]/}" ]]; then
        dns_check_hosts="$DNS_CHECK_HOSTS_DEFAULT"
    fi

    for dns_host in $dns_check_hosts; do
        if run_container_dns_probe "$dns_host"; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container DNS self-check passed for $dns_host."
            return 0
        fi
    done

    echo -en "[\e[1;33mWARN\e[0m] "
    echo "Container DNS self-check failed for probe hosts: $dns_check_hosts"
    return 1
}

## INSTALLATION FUNCTIONS

function install_service() {
    # Check if unit-file exists
    if [[ -f "$UNIT_FILE" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Unit file $UNIT_FILE already exists."
        install_update_timer
        return $?
    else
    # Write unit-file
        cat <<EOF > "$UNIT_FILE"
[Unit]
Description=UPRI: Sender Backend Service
After=docker.service raspberryshake.service
Requires=docker.service raspberryshake.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=myshake
ExecStart=/usr/local/bin/sender-backend START
ExecStop=/usr/local/bin/sender-backend STOP

[Install]
WantedBy=multi-user.target
EOF
      echo "Unit file $UNIT_FILE written."

      # Check if unit-file is successfully written as a disabled service
      systemctl daemon-reload
      systemctl --quiet enable "$SERVICE" >/dev/null 2>&1
      if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "$SERVICE installed as an enabled service."
          install_update_timer
          return $?
      else
          echo -en "[\e[1;31mFAILED\e[0m] "
          echo "Something went wrong in installing $SERVICE."
          return 1  # Failure
      fi
    fi
}

function install_update_timer() {
    local service_written=0
    local timer_written=0

    if [[ -f "$UPDATE_SERVICE_FILE" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Unit file $UPDATE_SERVICE_FILE already exists."
    else
        cat <<EOF > "$UPDATE_SERVICE_FILE"
[Unit]
Description=UPRI: Sender Stack Auto-update Service
ConditionPathExists=/usr/local/bin/sender-backend
ConditionPathExists=/usr/local/bin/sender-frontend
Wants=docker.service network-online.target
After=docker.service network-online.target

[Service]
Type=oneshot
User=myshake
ExecStart=/usr/bin/env bash -c '/usr/local/bin/sender-backend UPDATE; backend=\$?; /usr/local/bin/sender-frontend UPDATE; frontend=\$?; exit \$(( backend || frontend ))'

[Install]
WantedBy=multi-user.target
EOF
        echo "Unit file $UPDATE_SERVICE_FILE written."
        service_written=1
    fi

    if [[ -f "$UPDATE_TIMER_FILE" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Unit file $UPDATE_TIMER_FILE already exists."
    else
        cat <<EOF > "$UPDATE_TIMER_FILE"
[Unit]
Description=UPRI: Sender Stack Auto-update Timer

[Timer]
OnBootSec=15m
OnUnitActiveSec=1d
RandomizedDelaySec=30m
Unit=$UPDATE_SERVICE
Persistent=true

[Install]
WantedBy=timers.target
EOF
        echo "Unit file $UPDATE_TIMER_FILE written."
        timer_written=1
    fi

    systemctl daemon-reload
    if systemctl enable --now "$UPDATE_TIMER" >/dev/null 2>&1; then
        echo -en "[  \e[32mOK\e[0m  ] "
        if [[ $timer_written -eq 1 ]]; then
            echo "$UPDATE_TIMER installed, enabled, and started."
        else
            echo "$UPDATE_TIMER already enabled; ensured it is running."
        fi
        return 0
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to enable or start $UPDATE_TIMER."
        return 1
    fi
}

function uninstall_update_timer() {
    local removed=0

    systemctl stop "$UPDATE_TIMER" >/dev/null 2>&1
    systemctl disable "$UPDATE_TIMER" >/dev/null 2>&1

    if [[ -f "$UPDATE_TIMER_FILE" ]]; then
        rm "$UPDATE_TIMER_FILE"
        removed=1
    fi

    if [[ -f "$UPDATE_SERVICE_FILE" ]]; then
        rm "$UPDATE_SERVICE_FILE"
        removed=1
    fi

    systemctl daemon-reload

    echo -en "[  \e[32mOK\e[0m  ] "
    if [[ $removed -eq 1 ]]; then
        echo "Auto-update timer removed."
    else
        echo "Auto-update timer already removed."
    fi
    return 0
}

function pull_container() {
    docker pull "$IMAGE"
    if [[ $? -eq 0 ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Image $IMAGE pulled successfully."
        return 0
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to pull image $IMAGE."
        return 1
    fi
}

function create_network() {
    if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Docker network $DOCKER_NETWORK already exists."
        return 0 # Success
    else
        # create network
        docker network create \
            --driver bridge \
            --subnet 172.18.0.0/16 \
            --gateway 172.18.0.1 \
            --ip-range 172.18.0.0/24 \
            "$DOCKER_NETWORK"

        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Network $DOCKER_NETWORK created successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to create network $DOCKER_NETWORK."
            return 1
        fi

    fi
}

function create_container() {
    local dns_mode="${1:-auto}"
    local docker_network_flag

    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER already exists."
        return 0 # Success
    else
        # get IP of rshake accessible from within the container
        local host_ip
        host_ip="$(ip addr show docker0 | grep -Po 'inet \K[\d.]+' | head -n 1)"
        # set domain name on which host_ip will be accessible from within container
        local in_docker_hostname="docker-host"

        prepare_dns_flags "$dns_mode" || return 1
        docker_network_flag="$(get_docker_create_network_flag)"

        # create container
        # TODO: Change W1_PROD_IP to earthquake-hub domain /api (for production)
        docker create \
            --name "$CONTAINER" \
            --add-host "$in_docker_hostname:$host_ip" \
            --volume /sys/fs/cgroup:/sys/fs/cgroup:ro \
            --volume /opt/settings:/opt/settings:ro \
            --volume "$VOLUME":/app/localDBs \
            --env LOCALDBS_DIRECTORY=/app/localDBs \
            --env W1_PROD_IP=earthquake.science.upd.edu.ph/api \
            --log-driver json-file \
            --log-opt max-size=10m \
            --log-opt max-file=3 \
            --label "$DNS_MODE_LABEL_KEY=$dns_mode" \
            "${DNS_FLAGS[@]}" \
            "$docker_network_flag" "$DOCKER_NETWORK" \
            "$IMAGE"
            # 1st volume: workaround for docker's oci runtime error
            # 2nd volume: contains NET and STAT info
            # 3rd volume: will contain local file storage of sender-backend server
            # net should make sender-backend be accessible by name from frontend

        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container $CONTAINER created successfully (DNS mode: $dns_mode)."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to create container $CONTAINER."
            return 1
        fi
    fi
}

function start_container() {
    local dns_mode

    if [[ $(docker inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null) == "true" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER is already running."
        return 0
    else
        docker start "$CONTAINER"
        if [[ $? -ne 0 ]]; then
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to start container $CONTAINER."
            return 1
        fi

        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER started successfully."

        if check_container_dns_resolution; then
            return 0
        fi

        dns_mode="$(get_container_dns_mode)"
        if [[ "$dns_mode" == "host-policy" ]]; then
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Container DNS failed even in host-policy fallback mode."
            return 1
        fi

        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Recreating container with host-policy DNS fallback."

        docker stop "$CONTAINER" >/dev/null 2>&1
        if ! docker rm "$CONTAINER" >/dev/null 2>&1; then
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove container $CONTAINER before DNS fallback recreation."
            return 1
        fi

        if ! create_container "host-policy"; then
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Unable to create fallback container with host-policy DNS."
            return 1
        fi

        docker start "$CONTAINER"
        if [[ $? -ne 0 ]]; then
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to start fallback container $CONTAINER."
            return 1
        fi

        if check_container_dns_resolution; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container DNS recovered using host-policy fallback."
            return 0
        fi

        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Container DNS check still failing after host-policy fallback."
        return 1
    fi
}

function update_container() {
    stop_container
    remove_container
    pull_container || return 1
    create_network
    create_container
    start_container
}

## UNINSTALL FUNCTIONS
function stop_container() {
    if [[ $(docker inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null) == "true" ]]; then
        docker stop "$CONTAINER"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container $CONTAINER stopped successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to stop container $CONTAINER."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER is not running."
        return 0
    fi
}

function remove_container() {
    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        docker rm "$CONTAINER"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container $CONTAINER removed successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove container $CONTAINER."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER does not exist."
        return 0
    fi
}

function remove_image() {
    if docker inspect "$IMAGE" >/dev/null 2>&1; then
        docker rmi "$IMAGE"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Image $IMAGE removed successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove image $IMAGE."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Image $IMAGE does not exist."
        return 0
    fi
}

function remove_volume() {
    if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
        docker volume rm "$VOLUME"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Volume $VOLUME removed successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove volume $VOLUME."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Volume $VOLUME does not exist."
        return 0
    fi
}

function remove_network() {
    if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
        docker network rm "$DOCKER_NETWORK"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Network $DOCKER_NETWORK removed successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove network $DOCKER_NETWORK."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Network $DOCKER_NETWORK does not exist."
        return 0
    fi
}

function uninstall_service() {
    if [[ ! -f "$UNIT_FILE" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Unit file $UNIT_FILE does not exist."
        uninstall_update_timer
        return $?
    fi

    sudo systemctl --quiet stop "$SERVICE" >/dev/null 2>&1
    if [[ $? -eq 1 ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to stop service $UNIT_FILE."
        return 1
    fi

    sudo systemctl --quiet disable "$SERVICE" >/dev/null 2>&1
    if [[ $? -eq 1 ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to disable service $UNIT_FILE."
        return 1
    fi

    sudo rm "$UNIT_FILE"
    if [[ $? -eq 0 ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "$SERVICE uninstalled successfully."
        uninstall_update_timer
        return $?
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to remove unit file $UNIT_FILE."
        return 1
    fi
}

## execute function based on argument: INSTALL_SERVICE, NETWORK_SETUP, PULL, CREATE, START, STOP
case $1 in
    "INSTALL_SERVICE")
        install_service
        ;;
    "PULL")
        pull_container
        ;;
    "NETWORK_SETUP")
        create_network
        ;;
    "CREATE")
        create_container "$2"
        ;;
    "START")
        start_container
        ;;
    "UPDATE")
        update_container
        ;;
    "STOP")
        stop_container
        ;;
    "REMOVE_CONTAINER")
        remove_container
        ;;
    "REMOVE_IMAGE")
        remove_image
        ;;
    "REMOVE_VOLUME")
        remove_volume
        ;;
    "REMOVE_NETWORK")
        remove_network
        ;;
    "UNINSTALL_SERVICE")
        uninstall_service
        ;;
    "INSTALL_UPDATE_TIMER")
        install_update_timer
        ;;
    "UNINSTALL_UPDATE_TIMER")
        uninstall_update_timer
        ;;
    *)
        echo "Invalid argument. Usage: ./script.sh [INSTALL_SERVICE|INSTALL_UPDATE_TIMER|NETWORK_SETUP|PULL|CREATE|START|STOP|UPDATE|REMOVE_NETWORK|REMOVE_VOLUME|REMOVE_IMAGE|REMOVE_CONTAINER|UNINSTALL_SERVICE|UNINSTALL_UPDATE_TIMER]"
        ;;
esac
