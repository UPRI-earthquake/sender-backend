#!/bin/bash

# Constants
SERVICE="sender-frontend.service"
UNIT_FILE="/lib/systemd/system/$SERVICE"
CONTAINER="sender-frontend"
DOCKER_NETWORK="UPRI-docker-network"

SENDER_BUNDLE_TAG_DEFAULT="latest"
SENDER_FRONTEND_IMAGE_REPO_DEFAULT="ghcr.io/upri-earthquake/sender-frontend"
ALERT_RUNTIME_DIR_DEFAULT="/etc/upri/sender-runtime"
ALERT_RUNTIME_ENV_FILE_DEFAULT="${ALERT_RUNTIME_DIR_DEFAULT}/alert.env"
SENDER_BUNDLE_TAG="${SENDER_BUNDLE_TAG:-$SENDER_BUNDLE_TAG_DEFAULT}"
SENDER_FRONTEND_IMAGE_REPO="${SENDER_FRONTEND_IMAGE_REPO:-$SENDER_FRONTEND_IMAGE_REPO_DEFAULT}"
ALERT_RUNTIME_DIR="${ALERT_RUNTIME_DIR:-$ALERT_RUNTIME_DIR_DEFAULT}"
ALERT_RUNTIME_ENV_FILE="${ALERT_RUNTIME_ENV_FILE:-$ALERT_RUNTIME_ENV_FILE_DEFAULT}"
IMAGE="${SENDER_FRONTEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}"

AUTO_UPDATE_ALERT_ENDPOINT_DEFAULT="https://earthquake.science.upd.edu.ph/api/messaging/restricted/rshake-alert"
AUTO_UPDATE_ALERT_TIMEOUT_SEC_DEFAULT=8
AUTO_UPDATE_STATE_FILE_DEFAULT="/var/lib/upri-sender/update-state.json"
AUTO_UPDATE_STATE_FILE="${AUTO_UPDATE_STATE_FILE:-$AUTO_UPDATE_STATE_FILE_DEFAULT}"
LEGACY_AUTO_UPDATE_STATE_FILE="/tmp/upri-sender-auto-update-state.env"
AUTO_UPDATE_STATE_TTL_SEC_DEFAULT=3600
LAST_PULL_RESULT="unknown"
LAST_FRONTEND_IMAGE_REF="$IMAGE"
LAST_FRONTEND_DIGEST="unknown"
LAST_FRONTEND_BUNDLE_VERSION="unknown"

function load_alert_runtime_env() {
    if [[ -r "$ALERT_RUNTIME_ENV_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        . "$ALERT_RUNTIME_ENV_FILE"
        set +a
    fi
}

load_alert_runtime_env

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

function extract_image_repo() {
    local image_ref="$1"
    local repo="$image_ref"

    if [[ "$repo" == *@* ]]; then
        repo="${repo%@*}"
    elif [[ "$repo" == *:* ]]; then
        repo="${repo%:*}"
    fi

    printf "%s" "$repo"
}

function is_digest_ref() {
    local image_ref="$1"
    [[ "$image_ref" == *@sha256:* ]]
}

function resolve_image_ref() {
    local image_ref="$1"
    local repo
    local pull_output
    local pull_exit
    local digest_ref
    local digest

    repo="$(extract_image_repo "$image_ref")"
    pull_output="$(docker pull "$image_ref" 2>&1)"
    pull_exit=$?
    LAST_PULL_RESULT="$(classify_pull_state_from_output "$pull_output")"
    if [[ -n "$pull_output" ]]; then
        echo "$pull_output" >&2
    fi

    if [[ $pull_exit -ne 0 ]]; then
        return 1
    fi

    if is_digest_ref "$image_ref"; then
        printf "%s" "$image_ref"
        return 0
    fi

    digest_ref="$(docker image inspect --format '{{join .RepoDigests "\n"}}' "$image_ref" 2>/dev/null | awk -v repo="$repo" '$0 ~ "^" repo "@sha256:" {print; exit}')"
    if [[ -n "$digest_ref" ]]; then
        printf "%s" "$digest_ref"
        return 0
    fi

    digest="$(echo "$pull_output" | awk '/Digest: sha256:/ {print $2; exit}')"
    if [[ -n "$digest" ]]; then
        printf "%s@%s" "$repo" "$digest"
        return 0
    fi

    return 1
}

function get_container_repo_digest() {
    local container_name="$1"
    local repo="$2"
    local image_id
    local digest_ref

    image_id="$(docker inspect --format '{{.Image}}' "$container_name" 2>/dev/null || true)"
    if [[ -z "$image_id" ]]; then
        printf ""
        return 1
    fi

    digest_ref="$(docker image inspect --format '{{join .RepoDigests "\n"}}' "$image_id" 2>/dev/null | awk -v repo="$repo" '$0 ~ "^" repo "@sha256:" {print; exit}')"
    printf "%s" "$digest_ref"
}

function get_image_label() {
    local image_ref="$1"
    local label_key="$2"
    local value

    value="$(docker image inspect --format "{{ index .Config.Labels \"$label_key\" }}" "$image_ref" 2>/dev/null || true)"
    if [[ "$value" == "<no value>" ]]; then
        printf ""
        return 0
    fi
    printf "%s" "$value"
}

function ensure_container_restart_policy() {
    local container_name="$1"
    if ! docker inspect "$container_name" >/dev/null 2>&1; then
        return 0
    fi
    if docker update --restart unless-stopped "$container_name" >/dev/null 2>&1; then
        return 0
    fi
    echo -en "[\e[1;33mWARN\e[0m] "
    echo "Unable to enforce restart policy for container $container_name."
    return 1
}

function read_backend_update_state() {
    BACKEND_STATE_PRESENT=0
    BACKEND_EXIT=1
    BACKEND_PULL_STATE="unknown"
    BACKEND_SCRIPT_UPDATE_STATE="unknown"
    FRONTEND_SCRIPT_UPDATE_STATE="unknown"
    BACKEND_IMAGE="unknown"
    BACKEND_CONTAINER="unknown"
    BACKEND_DIGEST="unknown"
    FRONTEND_DIGEST="unknown"
    BUNDLE_TAG="unknown"
    BACKEND_BUNDLE_VERSION="unknown"
    FRONTEND_BUNDLE_VERSION="unknown"
    BACKEND_STATE_TS=0

    if [[ ! -r "$LEGACY_AUTO_UPDATE_STATE_FILE" ]]; then
        return 1
    fi

    while IFS='=' read -r key value; do
        case "$key" in
            BACKEND_EXIT) BACKEND_EXIT="$value" ;;
            BACKEND_PULL_STATE) BACKEND_PULL_STATE="$value" ;;
            BACKEND_SCRIPT_UPDATE_STATE) BACKEND_SCRIPT_UPDATE_STATE="$value" ;;
            FRONTEND_SCRIPT_UPDATE_STATE) FRONTEND_SCRIPT_UPDATE_STATE="$value" ;;
            BACKEND_IMAGE) BACKEND_IMAGE="$value" ;;
            BACKEND_CONTAINER) BACKEND_CONTAINER="$value" ;;
            BACKEND_DIGEST) BACKEND_DIGEST="$value" ;;
            FRONTEND_DIGEST) FRONTEND_DIGEST="$value" ;;
            BUNDLE_TAG) BUNDLE_TAG="$value" ;;
            BACKEND_BUNDLE_VERSION) BACKEND_BUNDLE_VERSION="$value" ;;
            FRONTEND_BUNDLE_VERSION) FRONTEND_BUNDLE_VERSION="$value" ;;
            STATE_TS) BACKEND_STATE_TS="$value" ;;
        esac
    done < "$LEGACY_AUTO_UPDATE_STATE_FILE"

    if ! [[ "$BACKEND_STATE_TS" =~ ^[0-9]+$ ]]; then
        rm -f "$LEGACY_AUTO_UPDATE_STATE_FILE" >/dev/null 2>&1
        return 1
    fi

    local now_ts ttl_sec age
    now_ts="$(date +%s)"
    ttl_sec="${AUTO_UPDATE_STATE_TTL_SEC:-$AUTO_UPDATE_STATE_TTL_SEC_DEFAULT}"
    if ! [[ "$ttl_sec" =~ ^[0-9]+$ ]]; then
        ttl_sec="$AUTO_UPDATE_STATE_TTL_SEC_DEFAULT"
    fi
    age=$((now_ts - BACKEND_STATE_TS))
    if (( age < 0 || age > ttl_sec )); then
        rm -f "$LEGACY_AUTO_UPDATE_STATE_FILE" >/dev/null 2>&1
        return 1
    fi

    BACKEND_STATE_PRESENT=1
    rm -f "$LEGACY_AUTO_UPDATE_STATE_FILE" >/dev/null 2>&1
    return 0
}

function post_auto_update_alert() {
    local alert_code="$1"
    local severity="$2"
    local summary="$3"
    local backend_exit="$4"
    local frontend_exit="$5"
    local backend_pull_state="$6"
    local frontend_pull_state="$7"
    local backend_image="$8"
    local frontend_image="$9"
    local backend_script_update="${10}"
    local frontend_script_update="${11}"
    local backend_digest="${12}"
    local frontend_digest="${13}"
    local bundle_tag="${14}"
    local bundle_version="${15}"
    local script_sync_result="${16}"

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
            host_fallback="sender-frontend"
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
{"schemaVersion":"$(json_escape "$schema_version")","messageId":"$(json_escape "$message_id")","type":"device.alert","occurredAt":"$(json_escape "$occurred_at")","device":$device_json,"status":"AUTO_UPDATE","alertCode":"$(json_escape "$alert_code")","severity":"$(json_escape "$severity")","summary":"$(json_escape "$summary")","details":{"source":"sender-stack-auto-update","notificationScope":"admin-only","executionMode":"legacy-chained-update","backendExitCode":$backend_exit,"frontendExitCode":$frontend_exit,"backendPullState":"$(json_escape "$backend_pull_state")","frontendPullState":"$(json_escape "$frontend_pull_state")","backendScriptUpdate":"$(json_escape "$backend_script_update")","frontendScriptUpdate":"$(json_escape "$frontend_script_update")","backendImage":"$(json_escape "$backend_image")","frontendImage":"$(json_escape "$frontend_image")","backendDigest":"$(json_escape "$backend_digest")","frontendDigest":"$(json_escape "$frontend_digest")","bundleTag":"$(json_escape "$bundle_tag")","bundleVersion":"$(json_escape "$bundle_version")","scriptSyncResult":"$(json_escape "$script_sync_result")"},"dedupeKey":"$(json_escape "$dedupe_key")"}
EOF
)

    local -a secret_header_args=()
    if [[ -n "${RSHAKE_ALERT_SHARED_SECRET:-}" ]]; then
        secret_header_args=(-H "X-RShake-Alert-Secret: ${RSHAKE_ALERT_SHARED_SECRET}")
    fi

    if curl --silent --show-error --max-time "$timeout_sec" \
        -H "Content-Type: application/json" \
        "${secret_header_args[@]}" \
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

function emit_chained_auto_update_alert() {
    local frontend_exit="$1"
    local frontend_pull_state="$2"
    local frontend_image_ref="$3"
    local frontend_digest="$4"
    local frontend_bundle_version="$5"
    local alert_code severity summary

    if ! read_backend_update_state; then
        return 0
    fi

    if [[ -z "$frontend_image_ref" ]]; then
        frontend_image_ref="$IMAGE"
    fi
    if [[ -z "$frontend_digest" ]]; then
        frontend_digest="unknown"
    fi
    if [[ -z "$frontend_bundle_version" ]]; then
        frontend_bundle_version="${FRONTEND_BUNDLE_VERSION:-unknown}"
    fi

    if [[ "$BACKEND_EXIT" != "0" || "$frontend_exit" != "0" ]]; then
        alert_code="AUTO_UPDATE_FAILED"
        severity="critical"
        summary="Sender auto-update executed with failures."
    elif [[ "$BACKEND_PULL_STATE" == "no-change" && "$frontend_pull_state" == "no-change" ]]; then
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
        "$BACKEND_EXIT" \
        "$frontend_exit" \
        "$BACKEND_PULL_STATE" \
        "$frontend_pull_state" \
        "$BACKEND_IMAGE" \
        "$frontend_image_ref" \
        "$BACKEND_SCRIPT_UPDATE_STATE" \
        "$FRONTEND_SCRIPT_UPDATE_STATE" \
        "$BACKEND_DIGEST" \
        "$frontend_digest" \
        "$BUNDLE_TAG" \
        "$BACKEND_BUNDLE_VERSION" \
        "managed-by-startup-hook"
    return 0
}

## INSTALL FUNCTIONS
function install_service() {
    # Check if unit-file exists
    if [[ -f "$UNIT_FILE" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Unit file $UNIT_FILE already exists."
    else
    # Write unit-file
        cat <<EOF > "$UNIT_FILE"
[Unit]
Description=UPRI: Sender Frontend Service
After=docker.service sender-backend.service
Requires=docker.service sender-backend.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=myshake
ExecStart=/usr/local/bin/sender-frontend START
ExecStop=/usr/local/bin/sender-frontend STOP

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
          return 0  # Success
      else
          echo -en "[\e[1;31mFAILED\e[0m] "
          echo "Something went wrong in installing $SERVICE."
          return 1  # Failure
      fi
    fi
}

function pull_container() {
    local requested_ref="${1:-${SENDER_FRONTEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}}"
    local resolved_ref

    LAST_PULL_RESULT="unknown"
    resolved_ref="$(resolve_image_ref "$requested_ref")" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to pull image $requested_ref."
        return 1
    }

    LAST_FRONTEND_IMAGE_REF="$resolved_ref"
    LAST_FRONTEND_DIGEST="${resolved_ref##*@}"
    LAST_FRONTEND_BUNDLE_VERSION="$(get_image_label "$resolved_ref" "org.upri.sender.bundle.version")"
    if [[ -z "$LAST_FRONTEND_BUNDLE_VERSION" ]]; then
        LAST_FRONTEND_BUNDLE_VERSION="unknown"
    fi

    echo -en "[  \e[32mOK\e[0m  ] "
    echo "Image $requested_ref resolved to $resolved_ref."
    return 0
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
            # 1st volume: workaround for docker's oci runtime error
            # 2nd volume: contains NET and STAT info
            # 3rd volume: will contain local file storage of sender-backend server
  
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
    local requested_ref="${1:-${SENDER_FRONTEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}}"
    local target_image_ref="$requested_ref"

    if ! is_digest_ref "$requested_ref"; then
        target_image_ref="$(resolve_image_ref "$requested_ref")" || {
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to resolve image for container creation: $requested_ref"
            return 1
        }
    fi
    LAST_FRONTEND_IMAGE_REF="$target_image_ref"
    LAST_FRONTEND_DIGEST="${target_image_ref##*@}"
    LAST_FRONTEND_BUNDLE_VERSION="$(get_image_label "$target_image_ref" "org.upri.sender.bundle.version")"
    if [[ -z "$LAST_FRONTEND_BUNDLE_VERSION" ]]; then
        LAST_FRONTEND_BUNDLE_VERSION="unknown"
    fi

    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER already exists."
        return 0 # Success
    else
        # create container
        docker create \
            --name "$CONTAINER" \
            --restart unless-stopped \
            --volume /sys/fs/cgroup:/sys/fs/cgroup:ro \
            --net UPRI-docker-network \
            --env REACT_APP_BACKEND_PORT=5001 \
            --env NGINX_PORT=3000 \
            --publish 0.0.0.0:3000:3000 \
            --log-driver json-file \
            --log-opt max-size=10m \
            --log-opt max-file=3 \
            "$target_image_ref"
            # volume: workaround for docker's oci runtime error
            # net: make sender-backend be accessible by name from frontend
            # publish: make port of host passthrough port of container

        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container $CONTAINER created successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to create container $CONTAINER."
            return 1
        fi
    fi
}

function start_container() {
    if [[ $(docker inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null) == "true" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER is already running."
        ensure_container_restart_policy "$CONTAINER" >/dev/null 2>&1 || true
        return 0
    else
        docker start "$CONTAINER"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container $CONTAINER started successfully."
            ensure_container_restart_policy "$CONTAINER" >/dev/null 2>&1 || true
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to start container $CONTAINER."
            return 1
        fi
    fi
}

function update_container() {
    local target_image_ref="$1"

    stop_container
    remove_container
    pull_container "$target_image_ref" || return 1
    create_network
    create_container "$LAST_FRONTEND_IMAGE_REF"
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
    local target_ref="${1:-${SENDER_FRONTEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}}"

    if docker image inspect "$target_ref" >/dev/null 2>&1; then
        docker rmi "$target_ref"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Image $target_ref removed successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove image $target_ref."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Image $target_ref does not exist."
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
        return 0
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
        return 0
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
        pull_container "$2"
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
        target_ref="${2:-${SENDER_FRONTEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}}"
        current_digest="$(get_container_repo_digest "$CONTAINER" "$SENDER_FRONTEND_IMAGE_REPO")"
        pull_container "$target_ref"
        pull_exit=$?
        target_resolved_ref="$LAST_FRONTEND_IMAGE_REF"

        if [[ $pull_exit -ne 0 ]]; then
            update_exit=$pull_exit
            frontend_pull_state="failed"
        elif [[ -n "$current_digest" && "$current_digest" == "$target_resolved_ref" ]]; then
            update_exit=0
            frontend_pull_state="no-change"
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Frontend image already matches target digest."
        else
            update_container "$target_resolved_ref"
            update_exit=$?
            if [[ $update_exit -eq 0 ]]; then
                frontend_pull_state="updated"
            else
                frontend_pull_state="failed"
            fi
        fi

        emit_chained_auto_update_alert \
            "$update_exit" \
            "$frontend_pull_state" \
            "$target_resolved_ref" \
            "$LAST_FRONTEND_DIGEST" \
            "$LAST_FRONTEND_BUNDLE_VERSION"
        exit "$update_exit"
        ;;
    "STOP")
        stop_container
        ;;
    "REMOVE_CONTAINER")
        remove_container
        ;;
    "REMOVE_IMAGE")
        remove_image "$2"
        ;;
    "REMOVE_NETWORK")
        remove_network
        ;;
    "UNINSTALL_SERVICE")
        uninstall_service
        ;;
    *)
        echo "Invalid argument. Usage: ./script.sh [INSTALL_SERVICE|NETWORK_SETUP|PULL [image-ref]|CREATE [image-ref]|START|STOP|UPDATE [image-ref]|REMOVE_NETWORK|REMOVE_IMAGE [image-ref]|REMOVE_CONTAINER|UNINSTALL_SERVICE]"
        ;;
esac
