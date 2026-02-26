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
AUTO_UPDATE_ALERT_ENDPOINT_DEFAULT="https://earthquake.science.upd.edu.ph/api/messaging/restricted/rshake-alert"
AUTO_UPDATE_ALERT_TIMEOUT_SEC_DEFAULT=8
LAST_PULL_RESULT="unknown"
AUTO_UPDATE_STATE_FILE="/tmp/upri-sender-auto-update-state.env"
SENDER_SCRIPT_AUTO_UPDATE_ENABLED_DEFAULT="true"
SENDER_SCRIPT_UPDATE_TIMEOUT_SEC_DEFAULT=20
BACKEND_SCRIPT_PATH="/usr/local/bin/sender-backend"
FRONTEND_SCRIPT_PATH="/usr/local/bin/sender-frontend"
SENDER_BACKEND_SCRIPT_URL_DEFAULT="https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/sender-improvements/sender-backend.sh"
SENDER_FRONTEND_SCRIPT_URL_DEFAULT="https://raw.githubusercontent.com/UPRI-earthquake/sender-frontend/sender-improvements/sender-frontend.sh"
SCRIPT_BACKEND_UPDATE_STATE="not-run"
SCRIPT_FRONTEND_UPDATE_STATE="not-run"

function json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/}"
    printf "%s" "$value"
}

function sanitize_token() {
    local value="$1"
    value="$(echo "$value" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/^-*//; s/-*$//')"
    if [[ -z "$value" ]]; then
        printf "unknown"
    else
        printf "%s" "$value"
    fi
}

function read_device_value() {
    local file_path="$1"
    if [[ -r "$file_path" ]]; then
        tr -d '\r' < "$file_path" | head -n 1 | xargs
        return 0
    fi
    printf ""
    return 1
}

function classify_pull_state_from_output() {
    local output="$1"
    if echo "$output" | grep -qi "Downloaded newer image"; then
        printf "updated"
        return 0
    fi
    if echo "$output" | grep -qi "Image is up to date\|up to date for"; then
        printf "no-change"
        return 0
    fi
    if echo "$output" | grep -qi "pulled successfully"; then
        printf "pulled"
        return 0
    fi
    printf "unknown"
}

function parse_bool() {
    local raw="$1"
    local normalized

    normalized="$(echo "${raw:-}" | tr '[:upper:]' '[:lower:]' | xargs)"
    case "$normalized" in
        1|true|yes|on)
            return 0
            ;;
        0|false|no|off)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

function install_script_payload() {
    local src_file="$1"
    local dest_file="$2"

    if install -m 0755 "$src_file" "$dest_file" >/dev/null 2>&1; then
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n install -m 0755 "$src_file" "$dest_file" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

function update_script_from_url() {
    local script_path="$1"
    local script_url="$2"
    local script_name="$3"
    local timeout_sec="$4"
    local tmp_file

    tmp_file="$(mktemp "/tmp/${script_name}.XXXXXX")" || {
        echo -en "[\e[1;33mWARN\e[0m] " >&2
        echo "Unable to allocate temp file for $script_name script update." >&2
        printf "tempfile-failed"
        return 1
    }

    if ! curl --fail --silent --show-error --location --max-time "$timeout_sec" "$script_url" -o "$tmp_file"; then
        rm -f "$tmp_file" >/dev/null 2>&1
        echo -en "[\e[1;33mWARN\e[0m] " >&2
        echo "Failed to download latest $script_name script." >&2
        printf "download-failed"
        return 1
    fi

    if ! head -n 1 "$tmp_file" | grep -q '^#!'; then
        rm -f "$tmp_file" >/dev/null 2>&1
        echo -en "[\e[1;33mWARN\e[0m] " >&2
        echo "Downloaded $script_name script failed basic validation." >&2
        printf "invalid-content"
        return 1
    fi

    chmod 0755 "$tmp_file" >/dev/null 2>&1 || true

    if [[ -r "$script_path" ]] && cmp -s "$tmp_file" "$script_path"; then
        rm -f "$tmp_file" >/dev/null 2>&1
        echo -en "[  \e[32mOK\e[0m  ] " >&2
        echo "$script_name script already up-to-date." >&2
        printf "no-change"
        return 0
    fi

    if install_script_payload "$tmp_file" "$script_path"; then
        rm -f "$tmp_file" >/dev/null 2>&1
        echo -en "[  \e[32mOK\e[0m  ] " >&2
        echo "$script_name script updated successfully." >&2
        printf "updated"
        return 0
    fi

    rm -f "$tmp_file" >/dev/null 2>&1
    echo -en "[\e[1;33mWARN\e[0m] " >&2
    echo "Insufficient permission to update $script_name script at $script_path." >&2
    printf "permission-denied"
    return 1
}

function refresh_sender_scripts() {
    local enabled_raw timeout_sec backend_url frontend_url

    SCRIPT_BACKEND_UPDATE_STATE="not-run"
    SCRIPT_FRONTEND_UPDATE_STATE="not-run"

    enabled_raw="${SENDER_SCRIPT_AUTO_UPDATE_ENABLED:-$SENDER_SCRIPT_AUTO_UPDATE_ENABLED_DEFAULT}"
    if ! parse_bool "$enabled_raw"; then
        SCRIPT_BACKEND_UPDATE_STATE="disabled"
        SCRIPT_FRONTEND_UPDATE_STATE="disabled"
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Sender script auto-update disabled by configuration."
        return 0
    fi

    timeout_sec="${SENDER_SCRIPT_UPDATE_TIMEOUT_SEC:-$SENDER_SCRIPT_UPDATE_TIMEOUT_SEC_DEFAULT}"
    if ! [[ "$timeout_sec" =~ ^[0-9]+$ ]]; then
        timeout_sec="$SENDER_SCRIPT_UPDATE_TIMEOUT_SEC_DEFAULT"
    fi

    backend_url="${SENDER_BACKEND_SCRIPT_URL:-$SENDER_BACKEND_SCRIPT_URL_DEFAULT}"
    frontend_url="${SENDER_FRONTEND_SCRIPT_URL:-$SENDER_FRONTEND_SCRIPT_URL_DEFAULT}"

    SCRIPT_BACKEND_UPDATE_STATE="$(update_script_from_url "$BACKEND_SCRIPT_PATH" "$backend_url" "sender-backend" "$timeout_sec")"
    SCRIPT_FRONTEND_UPDATE_STATE="$(update_script_from_url "$FRONTEND_SCRIPT_PATH" "$frontend_url" "sender-frontend" "$timeout_sec")"
}

function write_backend_update_state() {
    local backend_exit="$1"
    local backend_pull_state="$2"
    local backend_script_update="$3"
    local frontend_script_update="$4"
    local now_ts

    now_ts="$(date +%s)"
    cat <<EOF > "$AUTO_UPDATE_STATE_FILE"
BACKEND_EXIT=$backend_exit
BACKEND_PULL_STATE=$backend_pull_state
BACKEND_SCRIPT_UPDATE_STATE=$backend_script_update
FRONTEND_SCRIPT_UPDATE_STATE=$frontend_script_update
BACKEND_IMAGE=$IMAGE
BACKEND_CONTAINER=$CONTAINER
STATE_TS=$now_ts
EOF
}

function post_auto_update_alert() {
    local alert_code="$1"
    local severity="$2"
    local summary="$3"
    local backend_exit="$4"
    local frontend_exit="$5"
    local backend_pull_state="$6"
    local frontend_pull_state="$7"
    local backend_script_update="$8"
    local frontend_script_update="$9"

    if ! command -v curl >/dev/null 2>&1; then
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "curl is unavailable; skipping auto-update alert post."
        return 0
    fi

    local network station mac stream_id message_id occurred_at endpoint timeout_sec dedupe_key schema_version
    local device_json first_field
    network="$(read_device_value /opt/settings/sys/NET.txt)"
    station="$(read_device_value /opt/settings/sys/STN.txt)"
    mac="$(read_device_value /opt/settings/sys/eth-mac.txt)"
    stream_id="${network}_${station}_.*/MSEED"

    if [[ -z "${network}${station}${mac}" ]]; then
        local host_fallback
        host_fallback="$(hostname 2>/dev/null || true)"
        if [[ -z "$host_fallback" ]]; then
            host_fallback="sender-backend"
        fi
        stream_id="AUTO_UPDATE_${host_fallback}"
    fi

    occurred_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        message_id="$(cat /proc/sys/kernel/random/uuid)"
    else
        message_id="$(date +%s%N)-$RANDOM"
    fi

    endpoint="${AUTO_UPDATE_ALERT_ENDPOINT:-$AUTO_UPDATE_ALERT_ENDPOINT_DEFAULT}"
    timeout_sec="${AUTO_UPDATE_ALERT_TIMEOUT_SEC:-$AUTO_UPDATE_ALERT_TIMEOUT_SEC_DEFAULT}"
    schema_version="${RSHAKE_ALERT_SCHEMA_VERSION:-1.0}"
    dedupe_key="auto-update.$(sanitize_token "${station:-$stream_id}").$(sanitize_token "$alert_code")"

    device_json="{"
    first_field=1
    if [[ -n "$network" ]]; then
        device_json="${device_json}\"network\":\"$(json_escape "$network")\""
        first_field=0
    fi
    if [[ -n "$station" ]]; then
        if [[ $first_field -eq 0 ]]; then
            device_json="${device_json},"
        fi
        device_json="${device_json}\"station\":\"$(json_escape "$station")\""
        first_field=0
    fi
    if [[ -n "$stream_id" ]]; then
        if [[ $first_field -eq 0 ]]; then
            device_json="${device_json},"
        fi
        device_json="${device_json}\"streamId\":\"$(json_escape "$stream_id")\""
        first_field=0
    fi
    if [[ -n "$mac" ]]; then
        if [[ $first_field -eq 0 ]]; then
            device_json="${device_json},"
        fi
        device_json="${device_json}\"macAddress\":\"$(json_escape "$mac")\""
        first_field=0
    fi
    if [[ $first_field -eq 1 ]]; then
        device_json="${device_json}\"streamId\":\"AUTO_UPDATE_SENDER\""
    fi
    device_json="${device_json}}"

    local payload
    payload=$(cat <<EOF
{"schemaVersion":"$(json_escape "$schema_version")","messageId":"$(json_escape "$message_id")","type":"device.alert","occurredAt":"$(json_escape "$occurred_at")","device":$device_json,"status":"AUTO_UPDATE","alertCode":"$(json_escape "$alert_code")","severity":"$(json_escape "$severity")","summary":"$(json_escape "$summary")","details":{"source":"sender-stack-auto-update","notificationScope":"admin-only","backendExitCode":$backend_exit,"frontendExitCode":$frontend_exit,"backendPullState":"$(json_escape "$backend_pull_state")","frontendPullState":"$(json_escape "$frontend_pull_state")","backendScriptUpdate":"$(json_escape "$backend_script_update")","frontendScriptUpdate":"$(json_escape "$frontend_script_update")"},"dedupeKey":"$(json_escape "$dedupe_key")"}
EOF
)

    if curl --silent --show-error --max-time "$timeout_sec" \
        -H "Content-Type: application/json" \
        -X POST "$endpoint" \
        -d "$payload" >/dev/null; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Auto-update alert posted to central endpoint."
        return 0
    fi

    echo -en "[\e[1;33mWARN\e[0m] "
    echo "Failed to post auto-update alert to central endpoint."
    return 0
}

function update_stack_with_alert() {
    local backend_output backend_exit frontend_output frontend_exit backend_pull_state frontend_pull_state
    local alert_code severity summary

    rm -f "$AUTO_UPDATE_STATE_FILE" >/dev/null 2>&1
    refresh_sender_scripts

    LAST_PULL_RESULT="unknown"
    backend_output="$(update_container 2>&1)"
    backend_exit=$?
    if [[ -n "$backend_output" ]]; then
        echo "$backend_output"
    fi
    backend_pull_state="$LAST_PULL_RESULT"
    if [[ "$backend_pull_state" == "unknown" ]]; then
        backend_pull_state="$(classify_pull_state_from_output "$backend_output")"
    fi

    if [[ -x /usr/local/bin/sender-frontend ]]; then
        frontend_output="$(/usr/local/bin/sender-frontend UPDATE 2>&1)"
        frontend_exit=$?
        if [[ -n "$frontend_output" ]]; then
            echo "$frontend_output"
        fi
        frontend_pull_state="$(classify_pull_state_from_output "$frontend_output")"
    else
        frontend_exit=127
        frontend_pull_state="missing-script"
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "sender-frontend script is missing or not executable."
    fi

    if [[ $backend_exit -ne 0 || $frontend_exit -ne 0 ]]; then
        alert_code="AUTO_UPDATE_FAILED"
        severity="critical"
        summary="Sender auto-update executed with failures."
    elif [[ "$backend_pull_state" == "no-change" && "$frontend_pull_state" == "no-change" ]]; then
        alert_code="AUTO_UPDATE_NO_CHANGE"
        severity="info"
        summary="Sender auto-update executed; no newer images were available."
    else
        alert_code="AUTO_UPDATE_EXECUTED"
        severity="info"
        summary="Sender auto-update executed successfully."
    fi

    post_auto_update_alert \
        "$alert_code" \
        "$severity" \
        "$summary" \
        "$backend_exit" \
        "$frontend_exit" \
        "$backend_pull_state" \
        "$frontend_pull_state" \
        "$SCRIPT_BACKEND_UPDATE_STATE" \
        "$SCRIPT_FRONTEND_UPDATE_STATE"

    if [[ $backend_exit -ne 0 || $frontend_exit -ne 0 ]]; then
        return 1
    fi
    return 0
}

function update_container_with_state() {
    local backend_output backend_exit backend_pull_state

    refresh_sender_scripts
    LAST_PULL_RESULT="unknown"
    backend_output="$(update_container 2>&1)"
    backend_exit=$?
    if [[ -n "$backend_output" ]]; then
        echo "$backend_output"
    fi

    backend_pull_state="$LAST_PULL_RESULT"
    if [[ "$backend_pull_state" == "unknown" ]]; then
        backend_pull_state="$(classify_pull_state_from_output "$backend_output")"
    fi

    write_backend_update_state \
        "$backend_exit" \
        "$backend_pull_state" \
        "$SCRIPT_BACKEND_UPDATE_STATE" \
        "$SCRIPT_FRONTEND_UPDATE_STATE"
    return "$backend_exit"
}

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
ExecStart=/usr/local/bin/sender-backend UPDATE_STACK

[Install]
WantedBy=multi-user.target
EOF
    if [[ $? -ne 0 ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to write $UPDATE_SERVICE_FILE."
        return 1
    fi

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
    if [[ $? -ne 0 ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to write $UPDATE_TIMER_FILE."
        return 1
    fi

    echo -en "[  \e[32mOK\e[0m  ] "
    echo "Auto-update unit files written/updated."

    systemctl daemon-reload
    if systemctl enable --now "$UPDATE_TIMER" >/dev/null 2>&1; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "$UPDATE_TIMER enabled and started."
        return 0
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to enable or start $UPDATE_TIMER."
        return 1
    fi
}

function uninstall_update_timer() {
    local removed=0
    local failed=0

    sudo systemctl stop "$UPDATE_TIMER" >/dev/null 2>&1
    sudo systemctl disable "$UPDATE_TIMER" >/dev/null 2>&1

    if [[ -f "$UPDATE_TIMER_FILE" ]]; then
        if sudo rm -f "$UPDATE_TIMER_FILE"; then
            removed=1
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove $UPDATE_TIMER_FILE."
            failed=1
        fi
    fi

    if [[ -f "$UPDATE_SERVICE_FILE" ]]; then
        if sudo rm -f "$UPDATE_SERVICE_FILE"; then
            removed=1
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove $UPDATE_SERVICE_FILE."
            failed=1
        fi
    fi

    if ! sudo systemctl daemon-reload >/dev/null 2>&1; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to reload systemd daemon."
        failed=1
    fi

    if [[ $failed -eq 1 ]]; then
        return 1
    fi

    echo -en "[  \e[32mOK\e[0m  ] "
    if [[ $removed -eq 1 ]]; then
        echo "Auto-update timer removed."
    else
        echo "Auto-update timer already removed."
    fi
    return 0
}

function pull_container() {
    local pull_output
    local pull_exit

    pull_output="$(docker pull "$IMAGE" 2>&1)"
    pull_exit=$?
    LAST_PULL_RESULT="$(classify_pull_state_from_output "$pull_output")"
    if [[ -n "$pull_output" ]]; then
        echo "$pull_output"
    fi

    if [[ $pull_exit -eq 0 ]]; then
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
        update_container_with_state
        ;;
    "UPDATE_STACK")
        update_stack_with_alert
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
        echo "Invalid argument. Usage: ./script.sh [INSTALL_SERVICE|INSTALL_UPDATE_TIMER|NETWORK_SETUP|PULL|CREATE|START|STOP|UPDATE|UPDATE_STACK|REMOVE_NETWORK|REMOVE_VOLUME|REMOVE_IMAGE|REMOVE_CONTAINER|UNINSTALL_SERVICE|UNINSTALL_UPDATE_TIMER]"
        ;;
esac
