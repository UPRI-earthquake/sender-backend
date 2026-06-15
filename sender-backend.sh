#!/bin/bash

# Constants
SERVICE="sender-backend.service"
UNIT_FILE="/lib/systemd/system/$SERVICE"
CONTAINER="sender-backend"
VOLUME="UPRI-volume"
DOCKER_NETWORK="UPRI-docker-network"
UPDATE_SERVICE="sender-backend-update.service"
UPDATE_TIMER="sender-backend-update.timer"
UPDATE_SERVICE_FILE="/lib/systemd/system/$UPDATE_SERVICE"
UPDATE_TIMER_FILE="/lib/systemd/system/$UPDATE_TIMER"
WATCHDOG_SERVICE="sender-stack-watchdog.service"
WATCHDOG_TIMER="sender-stack-watchdog.timer"
WATCHDOG_SERVICE_FILE="/lib/systemd/system/$WATCHDOG_SERVICE"
WATCHDOG_TIMER_FILE="/lib/systemd/system/$WATCHDOG_TIMER"
REMOTE_TUNNEL_SERVICE="sender-remote-tunnel.service"
REMOTE_TUNNEL_SERVICE_FILE="/lib/systemd/system/$REMOTE_TUNNEL_SERVICE"

SENDER_BUNDLE_TAG_DEFAULT="latest"
SENDER_BACKEND_IMAGE_REPO_DEFAULT="ghcr.io/upri-earthquake/sender-backend"
SENDER_FRONTEND_IMAGE_REPO_DEFAULT="ghcr.io/upri-earthquake/sender-frontend"
SENDER_HOST_SCRIPTS_DIR_DEFAULT="/opt/upri/host-scripts"
CONTAINER_HOST_SCRIPTS_DIR_DEFAULT="/host-scripts"
ALERT_RUNTIME_DIR_DEFAULT="/etc/upri/sender-runtime"
ALERT_RUNTIME_ENV_FILE_DEFAULT="${ALERT_RUNTIME_DIR_DEFAULT}/alert.env"
CONTAINER_ALERT_RUNTIME_DIR_DEFAULT="/opt/upri/runtime"
CONTAINER_ALERT_RUNTIME_ENV_FILE_DEFAULT="${CONTAINER_ALERT_RUNTIME_DIR_DEFAULT}/alert.env"
SENDER_SCRIPT_SYNC_MODE_DEFAULT="fallback"
SENDER_SCRIPT_SYNC_TIMEOUT_SEC_DEFAULT=20

SENDER_BUNDLE_TAG="${SENDER_BUNDLE_TAG:-$SENDER_BUNDLE_TAG_DEFAULT}"
SENDER_BACKEND_IMAGE_REPO="${SENDER_BACKEND_IMAGE_REPO:-$SENDER_BACKEND_IMAGE_REPO_DEFAULT}"
SENDER_FRONTEND_IMAGE_REPO="${SENDER_FRONTEND_IMAGE_REPO:-$SENDER_FRONTEND_IMAGE_REPO_DEFAULT}"
SENDER_HOST_SCRIPTS_DIR="${SENDER_HOST_SCRIPTS_DIR:-$SENDER_HOST_SCRIPTS_DIR_DEFAULT}"
CONTAINER_HOST_SCRIPTS_DIR="${CONTAINER_HOST_SCRIPTS_DIR:-$CONTAINER_HOST_SCRIPTS_DIR_DEFAULT}"
ALERT_RUNTIME_DIR="${ALERT_RUNTIME_DIR:-$ALERT_RUNTIME_DIR_DEFAULT}"
ALERT_RUNTIME_ENV_FILE="${ALERT_RUNTIME_ENV_FILE:-$ALERT_RUNTIME_ENV_FILE_DEFAULT}"
CONTAINER_ALERT_RUNTIME_DIR="${CONTAINER_ALERT_RUNTIME_DIR:-$CONTAINER_ALERT_RUNTIME_DIR_DEFAULT}"
CONTAINER_ALERT_RUNTIME_ENV_FILE="${CONTAINER_ALERT_RUNTIME_ENV_FILE:-$CONTAINER_ALERT_RUNTIME_ENV_FILE_DEFAULT}"
SENDER_SCRIPT_SYNC_MODE="${SENDER_SCRIPT_SYNC_MODE:-$SENDER_SCRIPT_SYNC_MODE_DEFAULT}"
SENDER_SCRIPT_SYNC_TIMEOUT_SEC="${SENDER_SCRIPT_SYNC_TIMEOUT_SEC:-$SENDER_SCRIPT_SYNC_TIMEOUT_SEC_DEFAULT}"

IMAGE="${SENDER_BACKEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}"

# Optional DNS overrides for container resolution:
# - SENDER_BACKEND_DNS: comma/space-separated DNS servers (e.g., "10.0.0.2,10.0.0.3")
# - SENDER_BACKEND_DNS_FILE: file with DNS servers (one per line, or resolv.conf-style nameserver lines)
# - SENDER_BACKEND_DNS_CHECK_HOSTS: comma/space-separated probe hosts for DNS self-check
# - SENDER_BACKEND_DNS_CHECK_TIMEOUT_SEC: per-host DNS probe timeout in seconds (default: 8)

DNS_MODE_LABEL_KEY="upri.sender-backend.dns-mode"
DNS_CHECK_HOSTS_DEFAULT="earthquake.up.edu.ph github.com"
DNS_FLAGS=()
LEGACY_SENDER_DOMAIN="earthquake.science.upd.edu.ph"
CURRENT_SENDER_DOMAIN="earthquake.up.edu.ph"
W1_PROD_IP_DEFAULT="earthquake.up.edu.ph/api"
AUTO_UPDATE_ALERT_ENDPOINT_DEFAULT="https://earthquake.up.edu.ph/api/messaging/restricted/rshake-alert"
AUTO_UPDATE_ALERT_TIMEOUT_SEC_DEFAULT=8
DISK_ALERT_WARN_FREE_PCT_DEFAULT=15
DISK_ALERT_CRITICAL_FREE_PCT_DEFAULT=8
DISK_ALERT_RECOVERY_FREE_PCT_DEFAULT=20
DISK_ALERT_PATHS_DEFAULT="/,/app/localDBs"
DISK_ALERT_STATE_FILE_DEFAULT="/var/lib/upri-sender/disk-alert-state.env"
WATCHDOG_ENABLED_DEFAULT="true"
WATCHDOG_INTERVAL_MINUTES_DEFAULT=5
WATCHDOG_BACKEND_STOPPED_MAX_SEC_DEFAULT=900
WATCHDOG_FRONTEND_STOPPED_MAX_SEC_DEFAULT=900
WATCHDOG_BACKEND_UNHEALTHY_MAX_SEC_DEFAULT=900
WATCHDOG_FRONTEND_UNHEALTHY_MAX_SEC_DEFAULT=900
WATCHDOG_RESTART_COOLDOWN_SEC_DEFAULT=300
WATCHDOG_REMOTE_TUNNEL_ENABLED_DEFAULT="true"
WATCHDOG_REMOTE_TUNNEL_SERVICE_DOWN_MAX_SEC_DEFAULT=300
WATCHDOG_REMOTE_TUNNEL_DISCONNECTED_MAX_SEC_DEFAULT=900
WATCHDOG_STATE_FILE_DEFAULT="/var/lib/upri-sender/watchdog-state.env"
WATCHDOG_LOCK_FILE_DEFAULT="/tmp/upri-sender-maintenance.lock"
REMOTE_TUNNEL_ENV_FILE_DEFAULT="/etc/upri/sender-remote-tunnel.env"
REMOTE_TUNNEL_STATE_FILE_DEFAULT="/var/lib/upri-sender/remote-tunnel-state.json"
REMOTE_TUNNEL_PID_FILE_DEFAULT="/tmp/upri-sender-remote-tunnel.pid"
REMOTE_TUNNEL_AUTO_REGISTER_ENABLED_DEFAULT="false"
REMOTE_TUNNEL_ENROLL_ENDPOINT_DEFAULT=""
REMOTE_TUNNEL_ENROLL_TOKEN_DEFAULT=""
REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC_DEFAULT=15
REMOTE_TUNNEL_WSS_URL_DEFAULT=""
REMOTE_TUNNEL_WSS_PATH_PREFIX_DEFAULT=""
REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY_DEFAULT=""
REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY_DEFAULT=""
AUTO_UPDATE_ROLLBACK_ENABLED_DEFAULT="true"
AUTO_UPDATE_PRUNE_DANGLING_IMAGES_DEFAULT="true"
LAST_PULL_RESULT="unknown"
AUTO_UPDATE_STATE_FILE_DEFAULT="/var/lib/upri-sender/update-state.json"
AUTO_UPDATE_STATE_FILE="${AUTO_UPDATE_STATE_FILE:-$AUTO_UPDATE_STATE_FILE_DEFAULT}"
LEGACY_AUTO_UPDATE_STATE_FILE="/tmp/upri-sender-auto-update-state.env"
DISK_ALERT_WARN_FREE_PCT="${DISK_ALERT_WARN_FREE_PCT:-$DISK_ALERT_WARN_FREE_PCT_DEFAULT}"
DISK_ALERT_CRITICAL_FREE_PCT="${DISK_ALERT_CRITICAL_FREE_PCT:-$DISK_ALERT_CRITICAL_FREE_PCT_DEFAULT}"
DISK_ALERT_RECOVERY_FREE_PCT="${DISK_ALERT_RECOVERY_FREE_PCT:-$DISK_ALERT_RECOVERY_FREE_PCT_DEFAULT}"
DISK_ALERT_PATHS="${DISK_ALERT_PATHS:-$DISK_ALERT_PATHS_DEFAULT}"
DISK_ALERT_STATE_FILE="${DISK_ALERT_STATE_FILE:-$DISK_ALERT_STATE_FILE_DEFAULT}"
WATCHDOG_ENABLED="${WATCHDOG_ENABLED:-$WATCHDOG_ENABLED_DEFAULT}"
WATCHDOG_INTERVAL_MINUTES="${WATCHDOG_INTERVAL_MINUTES:-$WATCHDOG_INTERVAL_MINUTES_DEFAULT}"
WATCHDOG_BACKEND_STOPPED_MAX_SEC="${WATCHDOG_BACKEND_STOPPED_MAX_SEC:-$WATCHDOG_BACKEND_STOPPED_MAX_SEC_DEFAULT}"
WATCHDOG_FRONTEND_STOPPED_MAX_SEC="${WATCHDOG_FRONTEND_STOPPED_MAX_SEC:-$WATCHDOG_FRONTEND_STOPPED_MAX_SEC_DEFAULT}"
WATCHDOG_BACKEND_UNHEALTHY_MAX_SEC="${WATCHDOG_BACKEND_UNHEALTHY_MAX_SEC:-$WATCHDOG_BACKEND_UNHEALTHY_MAX_SEC_DEFAULT}"
WATCHDOG_FRONTEND_UNHEALTHY_MAX_SEC="${WATCHDOG_FRONTEND_UNHEALTHY_MAX_SEC:-$WATCHDOG_FRONTEND_UNHEALTHY_MAX_SEC_DEFAULT}"
WATCHDOG_RESTART_COOLDOWN_SEC="${WATCHDOG_RESTART_COOLDOWN_SEC:-$WATCHDOG_RESTART_COOLDOWN_SEC_DEFAULT}"
WATCHDOG_REMOTE_TUNNEL_ENABLED="${WATCHDOG_REMOTE_TUNNEL_ENABLED:-$WATCHDOG_REMOTE_TUNNEL_ENABLED_DEFAULT}"
WATCHDOG_REMOTE_TUNNEL_SERVICE_DOWN_MAX_SEC="${WATCHDOG_REMOTE_TUNNEL_SERVICE_DOWN_MAX_SEC:-$WATCHDOG_REMOTE_TUNNEL_SERVICE_DOWN_MAX_SEC_DEFAULT}"
WATCHDOG_REMOTE_TUNNEL_DISCONNECTED_MAX_SEC="${WATCHDOG_REMOTE_TUNNEL_DISCONNECTED_MAX_SEC:-$WATCHDOG_REMOTE_TUNNEL_DISCONNECTED_MAX_SEC_DEFAULT}"
WATCHDOG_STATE_FILE="${WATCHDOG_STATE_FILE:-$WATCHDOG_STATE_FILE_DEFAULT}"
WATCHDOG_LOCK_FILE="${WATCHDOG_LOCK_FILE:-$WATCHDOG_LOCK_FILE_DEFAULT}"
REMOTE_TUNNEL_ENV_FILE="${REMOTE_TUNNEL_ENV_FILE:-$REMOTE_TUNNEL_ENV_FILE_DEFAULT}"
REMOTE_TUNNEL_STATE_FILE="${REMOTE_TUNNEL_STATE_FILE:-$REMOTE_TUNNEL_STATE_FILE_DEFAULT}"
REMOTE_TUNNEL_PID_FILE="${REMOTE_TUNNEL_PID_FILE:-$REMOTE_TUNNEL_PID_FILE_DEFAULT}"
AUTO_UPDATE_ROLLBACK_ENABLED="${AUTO_UPDATE_ROLLBACK_ENABLED:-$AUTO_UPDATE_ROLLBACK_ENABLED_DEFAULT}"
AUTO_UPDATE_PRUNE_DANGLING_IMAGES="${AUTO_UPDATE_PRUNE_DANGLING_IMAGES:-$AUTO_UPDATE_PRUNE_DANGLING_IMAGES_DEFAULT}"

SENDER_SCRIPT_AUTO_UPDATE_ENABLED_DEFAULT="deprecated"
SENDER_BACKEND_SCRIPT_URL_DEFAULT="deprecated"
SENDER_FRONTEND_SCRIPT_URL_DEFAULT="deprecated"

SCRIPT_BACKEND_UPDATE_STATE="deprecated-ignored"
SCRIPT_FRONTEND_UPDATE_STATE="deprecated-ignored"
LAST_SCRIPT_SYNC_RESULT="managed-by-startup-hook"
LAST_ALERT_POST_RESULT="not-run"
LAST_BACKEND_IMAGE_REF="$IMAGE"
LAST_FRONTEND_IMAGE_REF="${SENDER_FRONTEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}"
LAST_BACKEND_DIGEST="unknown"
LAST_FRONTEND_DIGEST="unknown"
LAST_BUNDLE_VERSION="unknown"
LAST_FRONTEND_BUNDLE_VERSION="unknown"
LAST_STATE_FILE_PATH="$AUTO_UPDATE_STATE_FILE"
DISK_ALERT_LAST_LEVEL="ok"
DISK_ALERT_LAST_PATH=""
DISK_ALERT_LAST_FREE_PCT=100
DISK_ALERT_LAST_CHECK_AT=""
DISK_ALERT_STATE_FILE_PATH="$DISK_ALERT_STATE_FILE"
WATCHDOG_STATE_FILE_PATH="$WATCHDOG_STATE_FILE"
REMOTE_TUNNEL_STATE_FILE_PATH="$REMOTE_TUNNEL_STATE_FILE"
REMOTE_TUNNEL_ENABLED_VALUE="false"
REMOTE_TUNNEL_DEVICE_ID_VALUE=""
LAST_MIGRATION_RESULT="not-run"
LAST_MIGRATION_SUMMARY="not-run"
LAST_MIGRATION_CHANGED="false"
LAST_MIGRATION_BACKEND_ENV_RESULT="not-run"
LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT="not-run"
LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="not-run"
LAST_MIGRATION_NEXT_STEP="none"
LAST_MIGRATION_REMAINING="none"

function load_alert_runtime_env() {
    if [[ -r "$ALERT_RUNTIME_ENV_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        . "$ALERT_RUNTIME_ENV_FILE"
        set +a
    fi
}

load_alert_runtime_env
REMOTE_TUNNEL_REMOTE_PORT_VALUE=""
REMOTE_TUNNEL_LOCAL_HOST_VALUE="127.0.0.1"
REMOTE_TUNNEL_LOCAL_PORT_VALUE=22
REMOTE_TUNNEL_KEY_PATH_VALUE="/etc/upri/remote-tunnel/id_ed25519"
REMOTE_TUNNEL_AUTO_REGISTER_ENABLED_VALUE="$REMOTE_TUNNEL_AUTO_REGISTER_ENABLED_DEFAULT"
REMOTE_TUNNEL_ENROLL_ENDPOINT_VALUE="$REMOTE_TUNNEL_ENROLL_ENDPOINT_DEFAULT"
REMOTE_TUNNEL_ENROLL_TOKEN_VALUE="$REMOTE_TUNNEL_ENROLL_TOKEN_DEFAULT"
REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC_VALUE="$REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC_DEFAULT"
REMOTE_TUNNEL_WSS_URL_VALUE="$REMOTE_TUNNEL_WSS_URL_DEFAULT"
REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE="$REMOTE_TUNNEL_WSS_PATH_PREFIX_DEFAULT"
REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY_VALUE="$REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY_DEFAULT"
REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY_VALUE="$REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY_DEFAULT"
WATCHDOG_BACKEND_STOPPED_SINCE=0
WATCHDOG_FRONTEND_STOPPED_SINCE=0
WATCHDOG_BACKEND_UNHEALTHY_SINCE=0
WATCHDOG_FRONTEND_UNHEALTHY_SINCE=0
WATCHDOG_BACKEND_LAST_RESTART_TS=0
WATCHDOG_FRONTEND_LAST_RESTART_TS=0
WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE=0
WATCHDOG_TUNNEL_DISCONNECTED_SINCE=0
WATCHDOG_TUNNEL_LAST_RESTART_TS=0
LAST_ROLLBACK_RESULT="not-run"
LAST_ROLLBACK_BACKEND_EXIT=0
LAST_ROLLBACK_FRONTEND_EXIT=0
LAST_ROLLBACK_BACKEND_TARGET="none"
LAST_ROLLBACK_FRONTEND_TARGET="none"

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

function is_truthy() {
    local value="${1:-}"
    value="$(echo "$value" | tr '[:upper:]' '[:lower:]')"
    case "$value" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
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

function get_repo_digest_for_image_ref() {
    local image_ref="$1"
    local repo
    local digest_ref

    repo="$(extract_image_repo "$image_ref")"
    digest_ref="$(docker image inspect --format '{{join .RepoDigests "\n"}}' "$image_ref" 2>/dev/null | awk -v repo="$repo" '$0 ~ "^" repo "@sha256:" {print; exit}')"
    printf "%s" "$digest_ref"
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

function get_container_env_value() {
    local container_name="$1"
    local env_key="$2"

    docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container_name" 2>/dev/null \
        | awk -F= -v key="$env_key" '$1 == key {sub("^[^=]*=", ""); print; exit}'
}

function backend_container_config_drifted() {
    local current_w1
    local current_bundle_version

    if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
        return 1
    fi

    current_w1="$(get_container_env_value "$CONTAINER" "W1_PROD_IP")"
    if [[ "$current_w1" != "$W1_PROD_IP_DEFAULT" ]]; then
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Backend container env drift detected: W1_PROD_IP=${current_w1:-unset}, expected $W1_PROD_IP_DEFAULT."
        return 0
    fi

    current_bundle_version="$(get_container_env_value "$CONTAINER" "SENDER_IMAGE_BUNDLE_VERSION")"
    if [[ -n "$LAST_BUNDLE_VERSION" && "$LAST_BUNDLE_VERSION" != "unknown" && "$current_bundle_version" != "$LAST_BUNDLE_VERSION" ]]; then
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Backend container env drift detected: SENDER_IMAGE_BUNDLE_VERSION=${current_bundle_version:-unset}, expected $LAST_BUNDLE_VERSION."
        return 0
    fi

    return 1
}

function backend_container_has_legacy_domain_quiet() {
    local current_w1

    if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
        return 1
    fi

    current_w1="$(get_container_env_value "$CONTAINER" "W1_PROD_IP")"
    [[ "$current_w1" == *"$LEGACY_SENDER_DOMAIN"* ]]
}

function remote_tunnel_env_has_legacy_domain() {
    local env_file="${REMOTE_TUNNEL_ENV_FILE:-$REMOTE_TUNNEL_ENV_FILE_DEFAULT}"

    [[ -r "$env_file" ]] || return 1
    grep -q "$LEGACY_SENDER_DOMAIN" "$env_file" 2>/dev/null
}

function reset_auto_update_migration_state() {
    LAST_MIGRATION_RESULT="not-needed"
    LAST_MIGRATION_SUMMARY="No stale migration config was detected."
    LAST_MIGRATION_CHANGED="false"
    LAST_MIGRATION_BACKEND_ENV_RESULT="aligned"
    LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT="not-needed"
    LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="not-needed"
    LAST_MIGRATION_NEXT_STEP="none"
    LAST_MIGRATION_REMAINING="none"
}

function append_migration_follow_up() {
    local next_step="$1"
    local remaining="$2"

    if [[ -n "$next_step" && "$next_step" != "none" ]]; then
        if [[ "$LAST_MIGRATION_NEXT_STEP" == "none" ]]; then
            LAST_MIGRATION_NEXT_STEP="$next_step"
        elif [[ ",$LAST_MIGRATION_NEXT_STEP," != *",$next_step,"* ]]; then
            LAST_MIGRATION_NEXT_STEP="${LAST_MIGRATION_NEXT_STEP},${next_step}"
        fi
    fi

    if [[ -n "$remaining" && "$remaining" != "none" ]]; then
        if [[ "$LAST_MIGRATION_REMAINING" == "none" ]]; then
            LAST_MIGRATION_REMAINING="$remaining"
        elif [[ ",$LAST_MIGRATION_REMAINING," != *",$remaining,"* ]]; then
            LAST_MIGRATION_REMAINING="${LAST_MIGRATION_REMAINING},${remaining}"
        fi
    fi
}

function migrate_remote_tunnel_env_domains() {
    local env_file="${REMOTE_TUNNEL_ENV_FILE:-$REMOTE_TUNNEL_ENV_FILE_DEFAULT}"
    local tmp_file
    local config_status

    if [[ ! -r "$env_file" ]]; then
        LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT="missing-env-file"
        LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="not-needed"
        return 1
    fi

    if ! remote_tunnel_env_has_legacy_domain; then
        LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT="already-aligned"
        LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="not-needed"
        return 1
    fi

    tmp_file="$(mktemp "/tmp/upri-sender-remote-tunnel-migrate.XXXXXX")" || {
        LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT="rewrite-failed"
        LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="not-run"
        append_migration_follow_up "manually-update-remote-tunnel-env" "remote-tunnel-env-stale"
        return 1
    }

    sed "s/${LEGACY_SENDER_DOMAIN}/${CURRENT_SENDER_DOMAIN}/g" "$env_file" > "$tmp_file"
    if ! install_data_payload "$tmp_file" "$env_file" 0600; then
        rm -f "$tmp_file" >/dev/null 2>&1
        LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT="rewrite-failed"
        LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="not-run"
        append_migration_follow_up "manually-update-remote-tunnel-env" "remote-tunnel-env-stale"
        return 1
    fi
    rm -f "$tmp_file" >/dev/null 2>&1

    LAST_MIGRATION_CHANGED="true"
    LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT="migrated"

    load_remote_tunnel_env
    config_status=0
    remote_tunnel_validate_config >/dev/null 2>&1 || config_status=$?
    if ! is_truthy "${REMOTE_TUNNEL_ENABLED_VALUE:-false}"; then
        LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="skipped-disabled"
        return 0
    fi
    if [[ $config_status -eq 3 ]]; then
        LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="skipped-incomplete-config"
        append_migration_follow_up "complete-remote-tunnel-config" "remote-tunnel-config-incomplete"
        return 0
    fi
    if [[ ! -f "$REMOTE_TUNNEL_SERVICE_FILE" ]]; then
        LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="skipped-service-missing"
        append_migration_follow_up "install-remote-tunnel-service" "remote-tunnel-service-not-installed"
        return 0
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="skipped-no-systemctl"
        append_migration_follow_up "restart-remote-tunnel-service" "remote-tunnel-service-not-restarted"
        return 0
    fi
    if systemctl restart "$REMOTE_TUNNEL_SERVICE" >/dev/null 2>&1; then
        LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="restarted"
        return 0
    fi

    LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT="restart-failed"
    append_migration_follow_up "check-remote-tunnel-service" "remote-tunnel-service-restart-failed"
    return 0
}

function finalize_auto_update_migration_state() {
    local backend_was_stale="$1"
    local tunnel_was_stale="$2"
    local migration_detected=0
    local partial=0
    local failed=0

    reset_auto_update_migration_state

    if [[ "$backend_was_stale" == "1" ]]; then
        migration_detected=1
        if backend_container_has_legacy_domain_quiet; then
            LAST_MIGRATION_BACKEND_ENV_RESULT="stale-remains"
            append_migration_follow_up "recreate-backend-container" "backend-env-stale"
            partial=1
        else
            LAST_MIGRATION_CHANGED="true"
            LAST_MIGRATION_BACKEND_ENV_RESULT="migrated"
        fi
    fi

    if [[ "$tunnel_was_stale" == "1" ]]; then
        migration_detected=1
        if ! migrate_remote_tunnel_env_domains; then
            if [[ "$LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT" == "rewrite-failed" ]]; then
                failed=1
            elif [[ "$LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT" != "already-aligned" ]]; then
                partial=1
            fi
        fi
        if [[ "$LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT" == restart-failed || "$LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT" == skipped-incomplete-config || "$LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT" == skipped-service-missing || "$LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT" == skipped-no-systemctl ]]; then
            partial=1
        fi
    fi

    if [[ $migration_detected -eq 0 ]]; then
        LAST_MIGRATION_RESULT="not-needed"
        LAST_MIGRATION_SUMMARY="No stale migration config was detected."
        return 0
    fi

    if [[ $failed -eq 1 ]]; then
        LAST_MIGRATION_RESULT="failed"
        LAST_MIGRATION_SUMMARY="Auto-update detected stale migration config but could not rewrite all required host values."
        return 0
    fi

    if [[ $partial -eq 1 ]]; then
        LAST_MIGRATION_RESULT="partial"
        LAST_MIGRATION_SUMMARY="Auto-update migrated stale config values, but follow-up is still required to complete station migration."
        return 0
    fi

    LAST_MIGRATION_RESULT="completed"
    LAST_MIGRATION_SUMMARY="Auto-update migrated stale config values to the new server domain."
    return 0
}

function cleanup_dangling_images_compatible() {
    local dangling_ids=""
    local image_id=""
    local removed_count=0
    local failed_count=0

    if ! is_truthy "$AUTO_UPDATE_PRUNE_DANGLING_IMAGES"; then
        return 0
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Docker CLI not found; skipping dangling image cleanup."
        return 0
    fi

    # Use docker versions compatible with older RShake hosts (no `docker image prune` required).
    dangling_ids="$(docker images -f dangling=true -q 2>/dev/null | awk 'NF' | sort -u)"
    if [[ -z "$dangling_ids" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "No dangling Docker images to clean."
        return 0
    fi

    while IFS= read -r image_id; do
        [[ -n "$image_id" ]] || continue
        if docker rmi "$image_id" >/dev/null 2>&1; then
            removed_count=$((removed_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
    done <<< "$dangling_ids"

    if [[ $failed_count -gt 0 ]]; then
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Dangling image cleanup removed $removed_count image(s); $failed_count could not be removed."
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Dangling image cleanup removed $removed_count image(s)."
    fi

    return 0
}

function install_data_payload() {
    local src_file="$1"
    local dest_file="$2"
    local mode="${3:-0644}"

    if install -m "$mode" "$src_file" "$dest_file" >/dev/null 2>&1; then
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n install -m "$mode" "$src_file" "$dest_file" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

function resolve_remote_tunnel_state_file_path() {
    local state_file="$REMOTE_TUNNEL_STATE_FILE"
    local state_dir

    state_dir="$(dirname "$state_file")"
    if mkdir -p "$state_dir" >/dev/null 2>&1; then
        printf "%s" "$state_file"
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n mkdir -p "$state_dir" >/dev/null 2>&1; then
        printf "%s" "$state_file"
        return 0
    fi

    printf "/tmp/upri-sender/remote-tunnel-state.json"
}

function write_remote_tunnel_state() {
    local connected="$1"
    local last_connected_at="$2"
    local last_error="$3"
    local state_path
    local tmp_file
    local now_iso
    local connected_json="false"
    local last_connected_json="null"
    local last_error_json="null"
    local remote_port_json="null"
    local local_port_json="null"

    state_path="$(resolve_remote_tunnel_state_file_path)"
    REMOTE_TUNNEL_STATE_FILE_PATH="$state_path"

    if is_truthy "$connected"; then
        connected_json="true"
    fi
    if [[ -n "$last_connected_at" ]]; then
        last_connected_json="\"$(json_escape "$last_connected_at")\""
    fi
    if [[ -n "$last_error" ]]; then
        last_error_json="\"$(json_escape "$last_error")\""
    fi
    if [[ "${REMOTE_TUNNEL_REMOTE_PORT_VALUE:-}" =~ ^[0-9]+$ ]]; then
        remote_port_json="${REMOTE_TUNNEL_REMOTE_PORT_VALUE}"
    fi
    if [[ "${REMOTE_TUNNEL_LOCAL_PORT_VALUE:-}" =~ ^[0-9]+$ ]]; then
        local_port_json="${REMOTE_TUNNEL_LOCAL_PORT_VALUE}"
    fi

    now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    tmp_file="$(mktemp "/tmp/upri-sender-remote-tunnel-state.XXXXXX.json")" || return 1
    cat <<EOF > "$tmp_file"
{"updatedAt":"$(json_escape "$now_iso")","connected":$connected_json,"lastConnectedAt":$last_connected_json,"lastError":$last_error_json,"deviceId":"$(json_escape "${REMOTE_TUNNEL_DEVICE_ID_VALUE:-}")","remotePort":$remote_port_json,"localHost":"$(json_escape "${REMOTE_TUNNEL_LOCAL_HOST_VALUE:-127.0.0.1}")","localPort":$local_port_json,"wssUrl":"$(json_escape "${REMOTE_TUNNEL_WSS_URL_VALUE:-}")","wssPathPrefix":"$(json_escape "${REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE:-}")"}
EOF

    if ! install_data_payload "$tmp_file" "$state_path" 0644; then
        rm -f "$tmp_file" >/dev/null 2>&1
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Failed to write remote tunnel state to $state_path."
        return 1
    fi

    rm -f "$tmp_file" >/dev/null 2>&1
    return 0
}

function load_remote_tunnel_env() {
    local env_file="${REMOTE_TUNNEL_ENV_FILE:-$REMOTE_TUNNEL_ENV_FILE_DEFAULT}"
    local derived_enroll_endpoint

    REMOTE_TUNNEL_ENV_FILE="$env_file"
    if [[ -r "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file"
    fi

    REMOTE_TUNNEL_ENABLED_VALUE="${REMOTE_TUNNEL_ENABLED:-false}"
    REMOTE_TUNNEL_DEVICE_ID_VALUE="${REMOTE_TUNNEL_DEVICE_ID:-}"
    REMOTE_TUNNEL_REMOTE_PORT_VALUE="$(normalize_positive_int "${REMOTE_TUNNEL_REMOTE_PORT:-0}" 0 0)"
    REMOTE_TUNNEL_LOCAL_HOST_VALUE="${REMOTE_TUNNEL_LOCAL_HOST:-127.0.0.1}"
    REMOTE_TUNNEL_LOCAL_PORT_VALUE="$(normalize_positive_int "${REMOTE_TUNNEL_LOCAL_PORT:-22}" 22 1)"
    REMOTE_TUNNEL_KEY_PATH_VALUE="${REMOTE_TUNNEL_KEY_PATH:-/etc/upri/remote-tunnel/id_ed25519}"
    REMOTE_TUNNEL_AUTO_REGISTER_ENABLED_VALUE="${REMOTE_TUNNEL_AUTO_REGISTER_ENABLED:-$REMOTE_TUNNEL_AUTO_REGISTER_ENABLED_DEFAULT}"
    REMOTE_TUNNEL_ENROLL_TOKEN_VALUE="${REMOTE_TUNNEL_ENROLL_TOKEN:-$REMOTE_TUNNEL_ENROLL_TOKEN_DEFAULT}"
    REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC_VALUE="$(normalize_positive_int "${REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC:-$REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC_DEFAULT}" "$REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC_DEFAULT" 5)"
    REMOTE_TUNNEL_WSS_URL_VALUE="${REMOTE_TUNNEL_WSS_URL:-$REMOTE_TUNNEL_WSS_URL_DEFAULT}"
    REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE="${REMOTE_TUNNEL_WSS_PATH_PREFIX:-$REMOTE_TUNNEL_WSS_PATH_PREFIX_DEFAULT}"
    REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY_VALUE="${REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY:-$REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY_DEFAULT}"
    REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY_VALUE="${REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY:-$REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY_DEFAULT}"
    REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE="${REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE#/}"
    REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE="${REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE%/}"

    derived_enroll_endpoint=""
    if [[ -n "${W1_DEV_IP:-}" && -n "${W1_DEV_PORT:-}" ]]; then
        derived_enroll_endpoint="http://${W1_DEV_IP}:${W1_DEV_PORT}/device/tunnel/enroll"
    fi
    if [[ "${NODE_ENV:-}" == "production" && -n "${W1_PROD_IP:-}" ]]; then
        derived_enroll_endpoint="https://${W1_PROD_IP}/device/tunnel/enroll"
    elif [[ -z "$derived_enroll_endpoint" && -n "${W1_PROD_IP:-}" ]]; then
        derived_enroll_endpoint="https://${W1_PROD_IP}/device/tunnel/enroll"
    fi
    REMOTE_TUNNEL_ENROLL_ENDPOINT_VALUE="${REMOTE_TUNNEL_ENROLL_ENDPOINT:-$derived_enroll_endpoint}"

    REMOTE_TUNNEL_STATE_FILE="${REMOTE_TUNNEL_STATE_FILE:-$REMOTE_TUNNEL_STATE_FILE_DEFAULT}"
    REMOTE_TUNNEL_PID_FILE="${REMOTE_TUNNEL_PID_FILE:-$REMOTE_TUNNEL_PID_FILE_DEFAULT}"
    return 0
}

function remote_tunnel_config_is_complete() {
    if [[ -z "${REMOTE_TUNNEL_DEVICE_ID_VALUE:-}" ]]; then
        return 1
    fi
    if [[ -z "${REMOTE_TUNNEL_WSS_URL_VALUE:-}" ]]; then
        return 1
    fi
    if [[ -z "${REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE:-}" ]]; then
        return 1
    fi
    if ! [[ "${REMOTE_TUNNEL_REMOTE_PORT_VALUE:-}" =~ ^[0-9]+$ ]] || (( REMOTE_TUNNEL_REMOTE_PORT_VALUE < 1 || REMOTE_TUNNEL_REMOTE_PORT_VALUE > 65535 )); then
        return 1
    fi
    return 0
}

function remote_tunnel_extract_json_string() {
    local json="$1"
    local key="$2"
    local value

    value="$(printf '%s' "$json" | tr -d '\n' | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1)"
    value="${value//\\\\/\\}"
    value="${value//\\\"/\"}"
    value="${value//\\n/}"
    printf '%s' "$value"
}

function remote_tunnel_extract_json_number() {
    local json="$1"
    local key="$2"
    printf '%s' "$json" | tr -d '\n' | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" | head -n 1
}

function remote_tunnel_env_escape() {
    local value="$1"
    value="${value//$'\r'/}"
    value="${value//$'\n'/}"
    value="${value//\'/\'\\\'\'}"
    printf "'%s'" "$value"
}

function remote_tunnel_emit_env_line() {
    local key="$1"
    local value="${2-}"
    printf "%s=%s\n" "$key" "$(remote_tunnel_env_escape "$value")"
}

function persist_remote_tunnel_env() {
    local env_file="${REMOTE_TUNNEL_ENV_FILE:-$REMOTE_TUNNEL_ENV_FILE_DEFAULT}"
    local env_dir
    local tmp_file

    env_dir="$(dirname "$env_file")"
    if ! mkdir -p "$env_dir" >/dev/null 2>&1; then
        if ! (command -v sudo >/dev/null 2>&1 && sudo -n mkdir -p "$env_dir" >/dev/null 2>&1); then
            remote_tunnel_config_error "Unable to create remote tunnel env directory: $env_dir"
            return 1
        fi
    fi

    tmp_file="$(mktemp "/tmp/upri-sender-remote-tunnel-env.XXXXXX")" || return 1
    {
        printf "# Sender reverse tunnel configuration (wstunnel)\n"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_ENABLED" "${REMOTE_TUNNEL_ENABLED_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_DEVICE_ID" "${REMOTE_TUNNEL_DEVICE_ID_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_REMOTE_PORT" "${REMOTE_TUNNEL_REMOTE_PORT_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_LOCAL_HOST" "${REMOTE_TUNNEL_LOCAL_HOST_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_LOCAL_PORT" "${REMOTE_TUNNEL_LOCAL_PORT_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_KEY_PATH" "${REMOTE_TUNNEL_KEY_PATH_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_STATE_FILE" "${REMOTE_TUNNEL_STATE_FILE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_PID_FILE" "${REMOTE_TUNNEL_PID_FILE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_AUTO_REGISTER_ENABLED" "${REMOTE_TUNNEL_AUTO_REGISTER_ENABLED_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_ENROLL_ENDPOINT" "${REMOTE_TUNNEL_ENROLL_ENDPOINT_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_ENROLL_TOKEN" "${REMOTE_TUNNEL_ENROLL_TOKEN_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC" "${REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_WSS_URL" "${REMOTE_TUNNEL_WSS_URL_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_WSS_PATH_PREFIX" "${REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY" "${REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY_VALUE:-}"
        remote_tunnel_emit_env_line "REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY" "${REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY_VALUE:-}"
    } > "$tmp_file"

    if ! install_data_payload "$tmp_file" "$env_file" 0600; then
        rm -f "$tmp_file" >/dev/null 2>&1
        remote_tunnel_config_error "Unable to persist remote tunnel env file: $env_file"
        return 1
    fi

    rm -f "$tmp_file" >/dev/null 2>&1
    return 0
}

function remote_tunnel_apply_runtime_permissions() {
    local service_user="${REMOTE_TUNNEL_SERVICE_USER:-myshake}"
    local service_group
    local env_file="${REMOTE_TUNNEL_ENV_FILE:-$REMOTE_TUNNEL_ENV_FILE_DEFAULT}"
    local key_dir
    local dir_path

    if ! id -u "$service_user" >/dev/null 2>&1; then
        return 0
    fi

    service_group="$(id -gn "$service_user" 2>/dev/null || echo "$service_user")"
    key_dir="$(dirname "$REMOTE_TUNNEL_KEY_PATH_VALUE")"

    for dir_path in "$key_dir"; do
        [[ -n "$dir_path" ]] || continue
        mkdir -p "$dir_path" >/dev/null 2>&1 || true
        chown "$service_user:$service_group" "$dir_path" >/dev/null 2>&1 || true
        chmod 0700 "$dir_path" >/dev/null 2>&1 || true
    done

    if [[ -f "$env_file" ]]; then
        chown "$service_user:$service_group" "$env_file" >/dev/null 2>&1 || true
        chmod 0600 "$env_file" >/dev/null 2>&1 || true
    fi
    if [[ -f "$REMOTE_TUNNEL_KEY_PATH_VALUE" ]]; then
        chown "$service_user:$service_group" "$REMOTE_TUNNEL_KEY_PATH_VALUE" >/dev/null 2>&1 || true
        chmod 0600 "$REMOTE_TUNNEL_KEY_PATH_VALUE" >/dev/null 2>&1 || true
    fi
    if [[ -f "${REMOTE_TUNNEL_KEY_PATH_VALUE}.pub" ]]; then
        chown "$service_user:$service_group" "${REMOTE_TUNNEL_KEY_PATH_VALUE}.pub" >/dev/null 2>&1 || true
        chmod 0644 "${REMOTE_TUNNEL_KEY_PATH_VALUE}.pub" >/dev/null 2>&1 || true
    fi
    return 0
}

function remote_tunnel_provision_operator_key() {
    local operator_key_raw="${REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY_VALUE:-}"
    local operator_key
    local key_type
    local key_blob
    local service_user="${REMOTE_TUNNEL_SERVICE_USER:-myshake}"
    local service_group
    local user_home
    local ssh_dir
    local auth_keys
    local marker="upri-remote-actions-operator"
    local forced_command="/usr/local/bin/sender-backend REMOTE_ACTION_DISPATCH"
    local forced_entry
    local tmp_file
    local line

    operator_key="$(printf '%s' "$operator_key_raw" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [[ -z "$operator_key" ]]; then
        return 0
    fi

    key_type="$(printf '%s\n' "$operator_key" | awk '{print $1}')"
    key_blob="$(printf '%s\n' "$operator_key" | awk '{print $2}')"

    if [[ -z "$key_type" || -z "$key_blob" ]]; then
        remote_tunnel_config_error "REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY is invalid."
        return 1
    fi

    if ! id -u "$service_user" >/dev/null 2>&1; then
        remote_tunnel_config_error "Remote tunnel service user does not exist: $service_user"
        return 1
    fi

    service_group="$(id -gn "$service_user" 2>/dev/null || echo "$service_user")"
    user_home="$(getent passwd "$service_user" | cut -d: -f6)"
    if [[ -z "$user_home" ]]; then
        remote_tunnel_config_error "Unable to resolve home for remote tunnel service user: $service_user"
        return 1
    fi

    ssh_dir="${user_home}/.ssh"
    auth_keys="${ssh_dir}/authorized_keys"
    mkdir -p "$ssh_dir" >/dev/null 2>&1 || true
    touch "$auth_keys" >/dev/null 2>&1 || true

    chown "$service_user:$service_group" "$ssh_dir" "$auth_keys" >/dev/null 2>&1 || true
    chmod 0700 "$ssh_dir" >/dev/null 2>&1 || true
    chmod 0600 "$auth_keys" >/dev/null 2>&1 || true

    forced_entry="command=\"${forced_command}\",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding ${key_type} ${key_blob} ${marker}"
    tmp_file="$(mktemp "/tmp/upri-remote-action-authkeys.XXXXXX")" || return 1

    if [[ -f "$auth_keys" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if printf '%s' "$line" | grep -Fq "$marker"; then
                continue
            fi
            if [[ -n "$key_blob" ]] && printf '%s' "$line" | grep -Fq "$key_blob"; then
                continue
            fi
            printf '%s\n' "$line" >> "$tmp_file"
        done < "$auth_keys"
    fi

    printf '%s\n' "$forced_entry" >> "$tmp_file"
    if ! install_data_payload "$tmp_file" "$auth_keys" 0600; then
        rm -f "$tmp_file" >/dev/null 2>&1 || true
        remote_tunnel_config_error "Failed to install remote action operator key into ${auth_keys}"
        return 1
    fi
    rm -f "$tmp_file" >/dev/null 2>&1 || true

    chown "$service_user:$service_group" "$auth_keys" >/dev/null 2>&1 || true
    chmod 0600 "$auth_keys" >/dev/null 2>&1 || true
    return 0
}

function remote_tunnel_provision_operator_shell_key() {
    local operator_key_raw="${REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY_VALUE:-}"
    local operator_key
    local key_type
    local key_blob
    local service_user="${REMOTE_TUNNEL_SERVICE_USER:-myshake}"
    local service_group
    local user_home
    local ssh_dir
    local auth_keys
    local marker="upri-bastion-shell-operator"
    local shell_entry
    local tmp_file
    local line

    operator_key="$(printf '%s' "$operator_key_raw" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [[ -z "$operator_key" ]]; then
        return 0
    fi

    key_type="$(printf '%s\n' "$operator_key" | awk '{print $1}')"
    key_blob="$(printf '%s\n' "$operator_key" | awk '{print $2}')"

    if [[ -z "$key_type" || -z "$key_blob" ]]; then
        remote_tunnel_config_error "REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY is invalid."
        return 1
    fi

    if ! id -u "$service_user" >/dev/null 2>&1; then
        remote_tunnel_config_error "Remote tunnel service user does not exist: $service_user"
        return 1
    fi

    service_group="$(id -gn "$service_user" 2>/dev/null || echo "$service_user")"
    user_home="$(getent passwd "$service_user" | cut -d: -f6)"
    if [[ -z "$user_home" ]]; then
        remote_tunnel_config_error "Unable to resolve home for remote tunnel service user: $service_user"
        return 1
    fi

    ssh_dir="${user_home}/.ssh"
    auth_keys="${ssh_dir}/authorized_keys"
    mkdir -p "$ssh_dir" >/dev/null 2>&1 || true
    touch "$auth_keys" >/dev/null 2>&1 || true

    chown "$service_user:$service_group" "$ssh_dir" "$auth_keys" >/dev/null 2>&1 || true
    chmod 0700 "$ssh_dir" >/dev/null 2>&1 || true
    chmod 0600 "$auth_keys" >/dev/null 2>&1 || true

    # Allow interactive shell over the bastion reverse listener only.
    shell_entry="from=\"127.0.0.1,::1\",no-agent-forwarding,no-port-forwarding,no-X11-forwarding ${key_type} ${key_blob} ${marker}"
    tmp_file="$(mktemp "/tmp/upri-remote-shell-authkeys.XXXXXX")" || return 1

    if [[ -f "$auth_keys" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if printf '%s' "$line" | grep -Fq "$marker"; then
                continue
            fi
            if [[ -n "$key_blob" ]] && printf '%s' "$line" | grep -Fq "$key_blob"; then
                continue
            fi
            printf '%s\n' "$line" >> "$tmp_file"
        done < "$auth_keys"
    fi

    printf '%s\n' "$shell_entry" >> "$tmp_file"
    if ! install_data_payload "$tmp_file" "$auth_keys" 0600; then
        rm -f "$tmp_file" >/dev/null 2>&1 || true
        remote_tunnel_config_error "Failed to install operator shell key into ${auth_keys}"
        return 1
    fi
    rm -f "$tmp_file" >/dev/null 2>&1 || true

    chown "$service_user:$service_group" "$auth_keys" >/dev/null 2>&1 || true
    chmod 0600 "$auth_keys" >/dev/null 2>&1 || true
    return 0
}

function remote_tunnel_ensure_keypair() {
    local key_path="$REMOTE_TUNNEL_KEY_PATH_VALUE"
    local pub_path="${key_path}.pub"
    local key_dir

    if ! command -v ssh-keygen >/dev/null 2>&1; then
        remote_tunnel_config_error "ssh-keygen is required for tunnel auto-registration."
        return 1
    fi

    key_dir="$(dirname "$key_path")"
    if ! mkdir -p "$key_dir" >/dev/null 2>&1; then
        if ! (command -v sudo >/dev/null 2>&1 && sudo -n mkdir -p "$key_dir" >/dev/null 2>&1); then
            remote_tunnel_config_error "Unable to create remote tunnel key directory: $key_dir"
            return 1
        fi
    fi

    if [[ ! -s "$key_path" || ! -s "$pub_path" ]]; then
        rm -f "$key_path" "$pub_path" >/dev/null 2>&1 || true
        if ! ssh-keygen -q -t ed25519 -N "" -f "$key_path" >/dev/null 2>&1; then
            remote_tunnel_config_error "Failed to generate remote tunnel keypair at $key_path"
            return 1
        fi
    fi

    chmod 0600 "$key_path" >/dev/null 2>&1 || true
    chmod 0644 "$pub_path" >/dev/null 2>&1 || true
    return 0
}

function remote_tunnel_derive_device_id() {
    local network
    local station
    local host_name

    if [[ -n "${REMOTE_TUNNEL_DEVICE_ID_VALUE:-}" ]]; then
        return 0
    fi

    network="$(read_device_value /opt/settings/sys/NET.txt || true)"
    station="$(read_device_value /opt/settings/sys/STN.txt || true)"
    if [[ -n "$network" && -n "$station" ]]; then
        REMOTE_TUNNEL_DEVICE_ID_VALUE="${network}_${station}"
        return 0
    fi

    host_name="$(hostname 2>/dev/null || true)"
    host_name="$(sanitize_token "${host_name:-sender-device}")"
    REMOTE_TUNNEL_DEVICE_ID_VALUE="$host_name"
    return 0
}

function remote_tunnel_attempt_auto_register() {
    local endpoint="$REMOTE_TUNNEL_ENROLL_ENDPOINT_VALUE"
    local token="$REMOTE_TUNNEL_ENROLL_TOKEN_VALUE"
    local timeout_sec="$REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC_VALUE"
    local response_file
    local response_body
    local curl_exit=0
    local http_code
    local api_message
    local network
    local station
    local public_key
    local payload
    local remote_port_value
    local response_wss_url
    local response_wss_path_prefix
    local response_operator_public_key
    local response_operator_ssh_public_key

    if ! is_truthy "$REMOTE_TUNNEL_AUTO_REGISTER_ENABLED_VALUE"; then
        return 0
    fi
    if remote_tunnel_config_is_complete; then
        return 0
    fi

    if [[ -z "$endpoint" ]]; then
        remote_tunnel_config_error "REMOTE_TUNNEL_ENROLL_ENDPOINT is required when auto-register is enabled."
        return 1
    fi
    if [[ -z "$token" ]]; then
        remote_tunnel_config_error "REMOTE_TUNNEL_ENROLL_TOKEN is required when auto-register is enabled."
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        remote_tunnel_config_error "curl is required for tunnel auto-registration."
        return 1
    fi

    remote_tunnel_derive_device_id || return 1
    remote_tunnel_ensure_keypair || return 1

    public_key="$(head -n 1 "${REMOTE_TUNNEL_KEY_PATH_VALUE}.pub" 2>/dev/null | tr -d '\r')"
    if [[ -z "$public_key" ]]; then
        remote_tunnel_config_error "Unable to read tunnel public key from ${REMOTE_TUNNEL_KEY_PATH_VALUE}.pub"
        return 1
    fi

    network="$(read_device_value /opt/settings/sys/NET.txt || true)"
    station="$(read_device_value /opt/settings/sys/STN.txt || true)"

    payload="{\"deviceId\":\"$(json_escape "$REMOTE_TUNNEL_DEVICE_ID_VALUE")\",\"tunnelPublicKey\":\"$(json_escape "$public_key")\""
    if [[ -n "$network" ]]; then
        payload="${payload},\"network\":\"$(json_escape "$network")\""
    fi
    if [[ -n "$station" ]]; then
        payload="${payload},\"station\":\"$(json_escape "$station")\""
    fi
    payload="${payload}}"

    response_file="$(mktemp "/tmp/upri-sender-remote-tunnel-enroll.XXXXXX.json")" || return 1
    http_code="$(curl --silent --show-error \
        --connect-timeout "$timeout_sec" \
        --max-time "$timeout_sec" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -X POST "$endpoint" \
        -d "$payload" \
        -o "$response_file" \
        -w "%{http_code}" 2>/dev/null)" || curl_exit=$?

    if [[ $curl_exit -ne 0 ]]; then
        rm -f "$response_file" >/dev/null 2>&1 || true
        remote_tunnel_config_error "Auto-registration request failed (curl exit $curl_exit)."
        return 1
    fi

    response_body="$(tr -d '\r\n' < "$response_file")"
    rm -f "$response_file" >/dev/null 2>&1 || true

    if ! [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        api_message="$(remote_tunnel_extract_json_string "$response_body" "message")"
        if [[ -z "$api_message" ]]; then
            api_message="HTTP $http_code"
        fi
        remote_tunnel_config_error "Auto-registration rejected by enrollment API: $api_message"
        return 1
    fi

    remote_port_value="$(remote_tunnel_extract_json_number "$response_body" "REMOTE_TUNNEL_REMOTE_PORT")"
    response_wss_url="$(remote_tunnel_extract_json_string "$response_body" "REMOTE_TUNNEL_WSS_URL")"
    response_wss_path_prefix="$(remote_tunnel_extract_json_string "$response_body" "REMOTE_TUNNEL_WSS_PATH_PREFIX")"
    response_operator_public_key="$(remote_tunnel_extract_json_string "$response_body" "REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY")"
    response_operator_ssh_public_key="$(remote_tunnel_extract_json_string "$response_body" "REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY")"
    response_wss_path_prefix="${response_wss_path_prefix#/}"
    response_wss_path_prefix="${response_wss_path_prefix%/}"

    if [[ -z "$remote_port_value" ]]; then
        remote_tunnel_config_error "Enrollment API response missing required tunnel mapping fields."
        return 1
    fi

    REMOTE_TUNNEL_REMOTE_PORT_VALUE="$remote_port_value"
    if [[ -n "$response_wss_url" ]]; then
        REMOTE_TUNNEL_WSS_URL_VALUE="$response_wss_url"
    fi
    if [[ -n "$response_wss_path_prefix" ]]; then
        REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE="$response_wss_path_prefix"
    fi
    if [[ -n "$response_operator_public_key" ]]; then
        REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY_VALUE="$response_operator_public_key"
    fi
    if [[ -n "$response_operator_ssh_public_key" ]]; then
        REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY_VALUE="$response_operator_ssh_public_key"
    fi
    REMOTE_TUNNEL_ENABLED_VALUE="true"

    persist_remote_tunnel_env || return 1
    remote_tunnel_provision_operator_key || return 1
    remote_tunnel_provision_operator_shell_key || return 1

    echo -en "[  \e[32mOK\e[0m  ] "
    echo "Remote tunnel auto-registration succeeded (device=$REMOTE_TUNNEL_DEVICE_ID_VALUE port=$REMOTE_TUNNEL_REMOTE_PORT_VALUE)."
    return 0
}

function remote_tunnel_config_error() {
    REMOTE_TUNNEL_LAST_ERROR_VALUE="$1"
    echo -en "[\e[1;31mFAILED\e[0m] "
    echo "Remote tunnel configuration error: $REMOTE_TUNNEL_LAST_ERROR_VALUE"
    return 1
}

function remote_tunnel_validate_config() {
    if ! is_truthy "$REMOTE_TUNNEL_ENABLED_VALUE"; then
        REMOTE_TUNNEL_LAST_ERROR_VALUE="remote tunnel disabled (REMOTE_TUNNEL_ENABLED=false)"
        return 3
    fi
    if [[ -z "$REMOTE_TUNNEL_DEVICE_ID_VALUE" ]]; then
        remote_tunnel_config_error "REMOTE_TUNNEL_DEVICE_ID is required."
        return 1
    fi
    if [[ -z "$REMOTE_TUNNEL_WSS_URL_VALUE" ]]; then
        remote_tunnel_config_error "REMOTE_TUNNEL_WSS_URL is required."
        return 1
    fi
    if [[ ! "$REMOTE_TUNNEL_WSS_URL_VALUE" =~ ^wss?:// ]]; then
        remote_tunnel_config_error "REMOTE_TUNNEL_WSS_URL must start with ws:// or wss://."
        return 1
    fi
    if [[ -z "$REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE" ]]; then
        remote_tunnel_config_error "REMOTE_TUNNEL_WSS_PATH_PREFIX is required."
        return 1
    fi
    if [[ "$REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE" =~ [[:space:]] ]]; then
        remote_tunnel_config_error "REMOTE_TUNNEL_WSS_PATH_PREFIX must not contain whitespace."
        return 1
    fi
    if ! [[ "$REMOTE_TUNNEL_REMOTE_PORT_VALUE" =~ ^[0-9]+$ ]] || (( REMOTE_TUNNEL_REMOTE_PORT_VALUE < 1 || REMOTE_TUNNEL_REMOTE_PORT_VALUE > 65535 )); then
        remote_tunnel_config_error "REMOTE_TUNNEL_REMOTE_PORT must be between 1 and 65535."
        return 1
    fi
    if ! [[ "$REMOTE_TUNNEL_LOCAL_PORT_VALUE" =~ ^[0-9]+$ ]] || (( REMOTE_TUNNEL_LOCAL_PORT_VALUE < 1 || REMOTE_TUNNEL_LOCAL_PORT_VALUE > 65535 )); then
        remote_tunnel_config_error "REMOTE_TUNNEL_LOCAL_PORT must be between 1 and 65535."
        return 1
    fi
    if ! command -v wstunnel >/dev/null 2>&1; then
        remote_tunnel_config_error "wstunnel is required but not installed."
        return 1
    fi

    REMOTE_TUNNEL_LAST_ERROR_VALUE=""
    return 0
}

function remote_tunnel_start() {
    local wstunnel_pid=""
    local connected_at=""
    local exit_code=1
    local cleanup_reason="remote tunnel stopped by signal"
    local wstunnel_cmd

    load_remote_tunnel_env
    if ! remote_tunnel_attempt_auto_register; then
        write_remote_tunnel_state "false" "" "$REMOTE_TUNNEL_LAST_ERROR_VALUE" || true
        return 1
    fi
    # Reload env after auto-registration in case values were persisted.
    load_remote_tunnel_env
    remote_tunnel_validate_config
    case $? in
        0)
            ;;
        3)
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Remote tunnel disabled (REMOTE_TUNNEL_ENABLED=false)."
            write_remote_tunnel_state "false" "" "$REMOTE_TUNNEL_LAST_ERROR_VALUE" || true
            return 3
            ;;
        *)
            write_remote_tunnel_state "false" "" "$REMOTE_TUNNEL_LAST_ERROR_VALUE" || true
            return 1
            ;;
    esac

    remote_tunnel_apply_runtime_permissions || true
    remote_tunnel_provision_operator_key || true
    remote_tunnel_provision_operator_shell_key || true

    write_remote_tunnel_state "false" "" "connecting" || true
    trap 'cleanup_reason="remote tunnel stopped by system"; if [[ -n "$wstunnel_pid" ]] && kill -0 "$wstunnel_pid" >/dev/null 2>&1; then kill "$wstunnel_pid" >/dev/null 2>&1 || true; wait "$wstunnel_pid" >/dev/null 2>&1 || true; fi; rm -f "$REMOTE_TUNNEL_PID_FILE" >/dev/null 2>&1 || true; write_remote_tunnel_state "false" "$connected_at" "$cleanup_reason" || true; exit 0' INT TERM

    wstunnel_cmd=("wstunnel" "client" "-R" "tcp://127.0.0.1:${REMOTE_TUNNEL_REMOTE_PORT_VALUE}:${REMOTE_TUNNEL_LOCAL_HOST_VALUE}:${REMOTE_TUNNEL_LOCAL_PORT_VALUE}" "${REMOTE_TUNNEL_WSS_URL_VALUE}" "--tls-verify-certificate" "--http-upgrade-path-prefix" "${REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE}")
    if [[ -n "$REMOTE_TUNNEL_ENROLL_TOKEN_VALUE" ]]; then
        wstunnel_cmd+=("--http-headers" "Authorization: Bearer ${REMOTE_TUNNEL_ENROLL_TOKEN_VALUE}")
    fi
    "${wstunnel_cmd[@]}" &
    wstunnel_pid="$!"
    mkdir -p "$(dirname "$REMOTE_TUNNEL_PID_FILE")" >/dev/null 2>&1 || true
    printf "%s\n" "$wstunnel_pid" > "$REMOTE_TUNNEL_PID_FILE" 2>/dev/null || true

    sleep 2
    if ! kill -0 "$wstunnel_pid" >/dev/null 2>&1; then
        wait "$wstunnel_pid" >/dev/null 2>&1 || exit_code=$?
        rm -f "$REMOTE_TUNNEL_PID_FILE" >/dev/null 2>&1 || true
        write_remote_tunnel_state "false" "" "wstunnel exited before tunnel became ready (exit $exit_code)" || true
        trap - INT TERM
        return "$exit_code"
    fi

    connected_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    write_remote_tunnel_state "true" "$connected_at" "" || true

    wait "$wstunnel_pid" >/dev/null 2>&1
    exit_code=$?
    rm -f "$REMOTE_TUNNEL_PID_FILE" >/dev/null 2>&1 || true
    write_remote_tunnel_state "false" "$connected_at" "wstunnel exited (exit $exit_code)" || true
    trap - INT TERM
    return "$exit_code"
}

function remote_tunnel_stop() {
    local pid
    local scan_pid
    local scan_cmd
    local remote_bind_pattern=""
    local killed_any=0

    terminate_remote_tunnel_pid() {
        local target_pid="$1"
        local elapsed=0
        local wait_seconds=3

        [[ "$target_pid" =~ ^[0-9]+$ ]] || return 1

        if ! kill -0 "$target_pid" >/dev/null 2>&1; then
            return 0
        fi

        kill "$target_pid" >/dev/null 2>&1 || true
        while kill -0 "$target_pid" >/dev/null 2>&1; do
            if (( elapsed >= wait_seconds )); then
                kill -9 "$target_pid" >/dev/null 2>&1 || true
                break
            fi
            sleep 1
            ((elapsed++))
        done

        if kill -0 "$target_pid" >/dev/null 2>&1; then
            return 1
        fi
        return 0
    }

    load_remote_tunnel_env
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "$REMOTE_TUNNEL_SERVICE" >/dev/null 2>&1; then
            if systemctl stop "$REMOTE_TUNNEL_SERVICE" >/dev/null 2>&1 || (command -v sudo >/dev/null 2>&1 && sudo systemctl stop "$REMOTE_TUNNEL_SERVICE" >/dev/null 2>&1); then
                echo -en "[  \e[32mOK\e[0m  ] "
                echo "Stopped $REMOTE_TUNNEL_SERVICE."
            else
                echo -en "[\e[1;33mWARN\e[0m] "
                echo "Unable to stop $REMOTE_TUNNEL_SERVICE via systemctl."
            fi
        fi
    fi

    if [[ -r "$REMOTE_TUNNEL_PID_FILE" ]]; then
        pid="$(head -n 1 "$REMOTE_TUNNEL_PID_FILE" | tr -d '\r' | xargs)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" >/dev/null 2>&1; then
            if terminate_remote_tunnel_pid "$pid"; then
                killed_any=1
            fi
        fi
    fi

    if [[ "${REMOTE_TUNNEL_REMOTE_PORT_VALUE:-}" =~ ^[0-9]+$ ]] && (( REMOTE_TUNNEL_REMOTE_PORT_VALUE >= 1 && REMOTE_TUNNEL_REMOTE_PORT_VALUE <= 65535 )); then
        remote_bind_pattern="tcp://127.0.0.1:${REMOTE_TUNNEL_REMOTE_PORT_VALUE}:"
    fi

    if [[ -n "$remote_bind_pattern" ]]; then
        while IFS=$'\t' read -r scan_pid scan_cmd; do
            [[ "$scan_pid" =~ ^[0-9]+$ ]] || continue
            [[ "$scan_cmd" == *"wstunnel client"* ]] || continue
            [[ "$scan_cmd" == *"$remote_bind_pattern"* ]] || continue
            if terminate_remote_tunnel_pid "$scan_pid"; then
                killed_any=1
            fi
        done < <(ps -eo pid=,args= | awk '{pid=$1; $1=""; sub(/^[[:space:]]+/, "", $0); printf "%s\t%s\n", pid, $0}')
    fi

    rm -f "$REMOTE_TUNNEL_PID_FILE" >/dev/null 2>&1 || true
    if [[ $killed_any -eq 1 ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Stopped stale remote tunnel process(es)."
    fi
    write_remote_tunnel_state "false" "" "remote tunnel stopped by operator" || true
    return 0
}

function remote_tunnel_status() {
    load_remote_tunnel_env
    local token_state="unset"
    if [[ -n "${REMOTE_TUNNEL_ENROLL_TOKEN_VALUE:-}" ]]; then
        token_state="set"
    fi
    echo "Remote tunnel environment file: $REMOTE_TUNNEL_ENV_FILE"
    echo "Device ID: ${REMOTE_TUNNEL_DEVICE_ID_VALUE:-unset}"
    echo "Reverse bind: 127.0.0.1:${REMOTE_TUNNEL_REMOTE_PORT_VALUE:-unset} -> ${REMOTE_TUNNEL_LOCAL_HOST_VALUE}:${REMOTE_TUNNEL_LOCAL_PORT_VALUE}"
    echo "Key path: ${REMOTE_TUNNEL_KEY_PATH_VALUE:-unset}"
    echo "WSS URL: ${REMOTE_TUNNEL_WSS_URL_VALUE:-unset}"
    echo "WSS path prefix: ${REMOTE_TUNNEL_WSS_PATH_PREFIX_VALUE:-unset}"
    if [[ -n "${REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY_VALUE:-}" ]]; then
        echo "Remote action operator key: set"
    else
        echo "Remote action operator key: unset"
    fi
    if [[ -n "${REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY_VALUE:-}" ]]; then
        echo "Operator shell key: set"
    else
        echo "Operator shell key: unset"
    fi
    echo "Auto-register enabled: ${REMOTE_TUNNEL_AUTO_REGISTER_ENABLED_VALUE:-false}"
    echo "Enrollment endpoint: ${REMOTE_TUNNEL_ENROLL_ENDPOINT_VALUE:-unset}"
    echo "Enrollment token: $token_state"

    if command -v systemctl >/dev/null 2>&1; then
        local active_state enabled_state
        active_state="$(systemctl is-active "$REMOTE_TUNNEL_SERVICE" 2>/dev/null || true)"
        enabled_state="$(systemctl is-enabled "$REMOTE_TUNNEL_SERVICE" 2>/dev/null || true)"
        echo "Service: $REMOTE_TUNNEL_SERVICE (active=$active_state, enabled=$enabled_state)"
    fi

    REMOTE_TUNNEL_STATE_FILE_PATH="$(resolve_remote_tunnel_state_file_path)"
    echo "State file: $REMOTE_TUNNEL_STATE_FILE_PATH"
    if [[ -r "$REMOTE_TUNNEL_STATE_FILE_PATH" ]]; then
        cat "$REMOTE_TUNNEL_STATE_FILE_PATH"
    else
        echo '{"connected":false,"lastError":"remote tunnel state not found"}'
    fi
    return 0
}

function remote_action_decode_base64() {
    local encoded="$1"
    local decoded=""

    if decoded="$(printf '%s' "$encoded" | base64 --decode 2>/dev/null)"; then
        printf '%s' "$decoded"
        return 0
    fi
    if decoded="$(printf '%s' "$encoded" | base64 -d 2>/dev/null)"; then
        printf '%s' "$decoded"
        return 0
    fi
    return 1
}

function remote_action_emit_result() {
    local ok="$1"
    local code="$2"
    local message="$3"
    local action="${4:-}"
    local http_status="${5:-0}"
    local payload_json="${6:-null}"

    if [[ -z "$payload_json" ]]; then
        payload_json="null"
    fi

    printf 'REMOTE_ACTION_RESULT={"ok":%s,"code":"%s","message":"%s","action":"%s","httpStatus":%s,"payload":%s}\n' \
        "$ok" \
        "$(json_escape "$code")" \
        "$(json_escape "$message")" \
        "$(json_escape "$action")" \
        "$http_status" \
        "$payload_json"
}

function remote_action_request_sender_backend() {
    local target_path="$1"
    local request_body="$2"
    local request_method="${3:-POST}"
    local timeout_sec="${REMOTE_ACTION_TIMEOUT_SEC:-20}"
    local timeout_ms=20000
    local body_b64=""
    local output=""
    local exit_code=0
    local node_script=""

    REMOTE_ACTION_HTTP_STATUS=""
    REMOTE_ACTION_HTTP_BODY=""
    REMOTE_ACTION_REQUEST_ERROR=""

    request_method="$(printf '%s' "$request_method" | tr '[:lower:]' '[:upper:]' | xargs)"
    if [[ "$request_method" != "GET" && "$request_method" != "POST" ]]; then
        request_method="POST"
    fi

    if ! command -v docker >/dev/null 2>&1; then
        REMOTE_ACTION_REQUEST_ERROR="docker command is unavailable on host."
        return 1
    fi

    if ! [[ "$timeout_sec" =~ ^[0-9]+$ ]] || (( timeout_sec < 1 )); then
        timeout_sec=20
    fi
    timeout_ms=$((timeout_sec * 1000))
    body_b64="$(printf '%s' "$request_body" | base64 | tr -d '\r\n')"

    read -r -d '' node_script <<'EOF_NODE' || true
const http = require('http');

const path = process.env.REMOTE_ACTION_PATH || '/';
const bodyB64 = process.env.REMOTE_ACTION_BODY_B64 || '';
const timeoutMs = Number(process.env.REMOTE_ACTION_TIMEOUT_MS || '20000');
const backendPort = Number(process.env.REMOTE_ACTION_BACKEND_PORT || '5001');
const method = String(process.env.REMOTE_ACTION_METHOD || 'POST').toUpperCase();
let body = '{}';

try {
  body = Buffer.from(bodyB64, 'base64').toString('utf8');
} catch (_error) {
  process.stdout.write(`REQUEST_ERROR_B64=${Buffer.from('invalid request payload', 'utf8').toString('base64')}\n`);
  process.exit(2);
}

const req = http.request(
  {
    hostname: '127.0.0.1',
    port: Number.isFinite(backendPort) && backendPort > 0 ? backendPort : 5001,
    method,
    path,
    headers: {
      'Content-Type': 'application/json',
      ...(method === 'POST' ? { 'Content-Length': Buffer.byteLength(body) } : {}),
    },
    timeout: Number.isFinite(timeoutMs) && timeoutMs > 0 ? timeoutMs : 20000,
  },
  (res) => {
    let raw = '';
    res.on('data', (chunk) => {
      raw += chunk;
    });
    res.on('end', () => {
      process.stdout.write(`HTTP_STATUS=${res.statusCode}\n`);
      process.stdout.write(`HTTP_BODY_B64=${Buffer.from(raw || '', 'utf8').toString('base64')}\n`);
    });
  },
);

req.on('timeout', () => {
  req.destroy(new Error('request timeout'));
});

req.on('error', (error) => {
  process.stdout.write(`REQUEST_ERROR_B64=${Buffer.from(String(error && error.message ? error.message : 'request error'), 'utf8').toString('base64')}\n`);
  process.exit(3);
});

if (method === 'POST') {
  req.write(body);
}
req.end();
EOF_NODE

    # Some Docker builds on RShake hosts do not support `docker exec -e`.
    # Use positional args + inline env assignment inside `sh -c` for compatibility.
    output="$(
        printf '%s' "$node_script" | docker exec -i "$CONTAINER" sh -c '
            REMOTE_ACTION_PATH="$1" \
            REMOTE_ACTION_BODY_B64="$2" \
            REMOTE_ACTION_METHOD="$3" \
            REMOTE_ACTION_TIMEOUT_MS="$4" \
            REMOTE_ACTION_BACKEND_PORT="$5" \
            node -
        ' sh "$target_path" "$body_b64" "$request_method" "$timeout_ms" "${BACKEND_PROD_PORT:-5001}" 2>/dev/null
    )" || exit_code=$?

    REMOTE_ACTION_HTTP_STATUS="$(printf '%s\n' "$output" | sed -n 's/^HTTP_STATUS=//p' | tail -n 1)"
    local response_body_b64
    local request_error_b64
    response_body_b64="$(printf '%s\n' "$output" | sed -n 's/^HTTP_BODY_B64=//p' | tail -n 1)"
    request_error_b64="$(printf '%s\n' "$output" | sed -n 's/^REQUEST_ERROR_B64=//p' | tail -n 1)"

    if [[ -n "$response_body_b64" ]]; then
        REMOTE_ACTION_HTTP_BODY="$(remote_action_decode_base64 "$response_body_b64" || true)"
    fi
    if [[ -n "$request_error_b64" ]]; then
        REMOTE_ACTION_REQUEST_ERROR="$(remote_action_decode_base64 "$request_error_b64" || true)"
    fi

    if [[ $exit_code -ne 0 ]]; then
        if [[ -z "$REMOTE_ACTION_REQUEST_ERROR" ]]; then
            REMOTE_ACTION_REQUEST_ERROR="docker exec request failed (exit ${exit_code})."
        fi
        return 1
    fi

    if [[ -z "$REMOTE_ACTION_HTTP_STATUS" ]]; then
        REMOTE_ACTION_REQUEST_ERROR="${REMOTE_ACTION_REQUEST_ERROR:-missing HTTP status from local sender request.}"
        return 1
    fi
    return 0
}

function remote_action_execute() {
    local action_raw="${1:-}"
    local payload_b64="${2:-}"
    local action=""
    local payload_json="{}"
    local username=""
    local password=""
    local longitude=""
    local latitude=""
    local elevation=""
    local institution_name=""
    local url=""
    local request_body="{}"
    local request_path=""
    local request_method="POST"
    local response_message=""
    local response_payload_json="null"
    local status_code=0
    local body_b64=""

    action="$(printf '%s' "$action_raw" | tr '[:lower:]' '[:upper:]' | xargs)"
    if [[ -z "$action" ]]; then
        remote_action_emit_result "false" "invalid_action" "Missing action." "$action" 400
        return 1
    fi

    if [[ -n "$payload_b64" ]]; then
        if ! payload_json="$(remote_action_decode_base64 "$payload_b64")"; then
            remote_action_emit_result "false" "invalid_payload" "Unable to decode remote action payload." "$action" 400
            return 1
        fi
    fi

    case "$action" in
        "UNLINK")
            request_path="/device/unlink"
            request_body="{}"
            request_method="POST"
            ;;
        "RELINK")
            username="$(remote_tunnel_extract_json_string "$payload_json" "username")"
            password="$(remote_tunnel_extract_json_string "$payload_json" "password")"
            longitude="$(remote_tunnel_extract_json_string "$payload_json" "longitude")"
            latitude="$(remote_tunnel_extract_json_string "$payload_json" "latitude")"
            elevation="$(remote_tunnel_extract_json_string "$payload_json" "elevation")"
            if [[ -z "$username" || -z "$password" || -z "$longitude" || -z "$latitude" || -z "$elevation" ]]; then
                remote_action_emit_result "false" "invalid_payload" "Relink requires username, password, longitude, latitude, and elevation." "$action" 400
                return 1
            fi
            request_path="/device/link"
            request_body="{\"username\":\"$(json_escape "$username")\",\"password\":\"$(json_escape "$password")\",\"longitude\":\"$(json_escape "$longitude")\",\"latitude\":\"$(json_escape "$latitude")\",\"elevation\":\"$(json_escape "$elevation")\"}"
            request_method="POST"
            ;;
        "ADD_SERVER")
            institution_name="$(remote_tunnel_extract_json_string "$payload_json" "institutionName")"
            url="$(remote_tunnel_extract_json_string "$payload_json" "url")"
            if [[ -z "$institution_name" || -z "$url" ]]; then
                remote_action_emit_result "false" "invalid_payload" "Add server requires institutionName and url." "$action" 400
                return 1
            fi
            request_path="/servers/add"
            request_body="{\"institutionName\":\"$(json_escape "$institution_name")\",\"url\":\"$(json_escape "$url")\"}"
            request_method="POST"
            ;;
        "REMOVE_SERVER")
            url="$(remote_tunnel_extract_json_string "$payload_json" "url")"
            if [[ -z "$url" ]]; then
                remote_action_emit_result "false" "invalid_payload" "Remove server requires url." "$action" 400
                return 1
            fi
            request_path="/servers/remove"
            request_body="{\"url\":\"$(json_escape "$url")\"}"
            request_method="POST"
            ;;
        "LIST_SERVERS")
            request_path="/stream/status"
            request_body="{}"
            request_method="GET"
            ;;
        *)
            remote_action_emit_result "false" "unsupported_action" "Unsupported remote action." "$action" 400
            return 1
            ;;
    esac

    if ! remote_action_request_sender_backend "$request_path" "$request_body" "$request_method"; then
        remote_action_emit_result "false" "request_failed" "${REMOTE_ACTION_REQUEST_ERROR:-Failed to execute local sender request.}" "$action" 502
        return 1
    fi

    status_code="$REMOTE_ACTION_HTTP_STATUS"

    if [[ "$action" == "LIST_SERVERS" ]]; then
        if [[ "$status_code" =~ ^2[0-9][0-9]$ ]]; then
            body_b64="$(printf '%s' "${REMOTE_ACTION_HTTP_BODY:-{}}" | base64 | tr -d '\r\n')"
            response_payload_json="{\"serversBodyB64\":\"$(json_escape "$body_b64")\"}"
            remote_action_emit_result "true" "success" "Remote servers listed." "$action" "$status_code" "$response_payload_json"
            return 0
        fi
        response_message="$(remote_tunnel_extract_json_string "${REMOTE_ACTION_HTTP_BODY:-}" "message")"
        if [[ -z "$response_message" ]]; then
            response_message="Unable to list remote servers."
        fi
        remote_action_emit_result "false" "remote_failed" "$response_message" "$action" "$status_code"
        return 1
    fi

    response_message="$(remote_tunnel_extract_json_string "${REMOTE_ACTION_HTTP_BODY:-}" "message")"
    if [[ -z "$response_message" ]]; then
        response_message="Remote action processed."
    fi

    if [[ "$status_code" =~ ^2[0-9][0-9]$ ]]; then
        remote_action_emit_result "true" "success" "$response_message" "$action" "$status_code"
        return 0
    fi

    remote_action_emit_result "false" "remote_failed" "$response_message" "$action" "$status_code"
    return 1
}

function remote_action_dispatch() {
    local original_command="${SSH_ORIGINAL_COMMAND:-}"
    local command_name=""
    local action=""
    local payload_b64=""
    local extra=""

    if [[ -z "$original_command" ]]; then
        remote_action_emit_result "false" "invalid_command" "Missing SSH_ORIGINAL_COMMAND for remote action dispatch." "" 400
        return 1
    fi

    read -r command_name action payload_b64 extra <<< "$original_command"
    if [[ "$command_name" != "REMOTE_ACTION_EXECUTE" ]]; then
        remote_action_emit_result "false" "invalid_command" "Unsupported remote command." "" 400
        return 1
    fi
    if [[ -n "$extra" ]]; then
        remote_action_emit_result "false" "invalid_command" "Unexpected remote command arguments." "" 400
        return 1
    fi

    remote_action_execute "$action" "$payload_b64"
}

function resolve_state_file_path() {
    local state_file="$AUTO_UPDATE_STATE_FILE"
    local state_dir

    state_dir="$(dirname "$state_file")"
    if mkdir -p "$state_dir" >/dev/null 2>&1; then
        printf "%s" "$state_file"
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n mkdir -p "$state_dir" >/dev/null 2>&1; then
        printf "%s" "$state_file"
        return 0
    fi

    printf "/tmp/upri-sender/update-state.json"
}

function normalize_percent_value() {
    local raw="$1"
    local fallback="$2"
    if [[ "$raw" =~ ^[0-9]+$ ]] && (( raw >= 0 && raw <= 100 )); then
        printf "%s" "$raw"
        return 0
    fi
    printf "%s" "$fallback"
}

function resolve_disk_alert_state_file_path() {
    local state_file="$DISK_ALERT_STATE_FILE"
    local state_dir

    state_dir="$(dirname "$state_file")"
    if mkdir -p "$state_dir" >/dev/null 2>&1; then
        printf "%s" "$state_file"
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n mkdir -p "$state_dir" >/dev/null 2>&1; then
        printf "%s" "$state_file"
        return 0
    fi

    printf "/tmp/upri-sender/disk-alert-state.env"
}

function load_disk_alert_state() {
    local state_path
    local key
    local value

    DISK_ALERT_LAST_LEVEL="ok"
    DISK_ALERT_LAST_PATH=""
    DISK_ALERT_LAST_FREE_PCT=100
    DISK_ALERT_LAST_CHECK_AT=""

    state_path="$(resolve_disk_alert_state_file_path)"
    DISK_ALERT_STATE_FILE_PATH="$state_path"

    if [[ ! -r "$state_path" ]]; then
        return 0
    fi

    while IFS='=' read -r key value; do
        case "$key" in
            DISK_ALERT_LEVEL)
                case "$value" in
                    ok|warn|critical)
                        DISK_ALERT_LAST_LEVEL="$value"
                        ;;
                esac
                ;;
            DISK_ALERT_PATH)
                DISK_ALERT_LAST_PATH="$value"
                ;;
            DISK_ALERT_FREE_PCT)
                if [[ "$value" =~ ^[0-9]+$ ]]; then
                    DISK_ALERT_LAST_FREE_PCT="$value"
                fi
                ;;
            DISK_ALERT_LAST_CHECK_AT)
                DISK_ALERT_LAST_CHECK_AT="$value"
                ;;
        esac
    done < "$state_path"
}

function write_disk_alert_state() {
    local level="$1"
    local path_value="$2"
    local free_pct="$3"
    local checked_at="$4"
    local state_path tmp_file

    state_path="$(resolve_disk_alert_state_file_path)"
    DISK_ALERT_STATE_FILE_PATH="$state_path"

    tmp_file="$(mktemp "/tmp/upri-sender-disk-state.XXXXXX.env")" || return 1
    cat <<EOF > "$tmp_file"
DISK_ALERT_LEVEL=$level
DISK_ALERT_PATH=$path_value
DISK_ALERT_FREE_PCT=$free_pct
DISK_ALERT_LAST_CHECK_AT=$checked_at
EOF

    if ! install_data_payload "$tmp_file" "$state_path" 0644; then
        rm -f "$tmp_file" >/dev/null 2>&1
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Failed to write disk alert state to $state_path."
        return 1
    fi

    rm -f "$tmp_file" >/dev/null 2>&1
    return 0
}

function classify_disk_alert_level() {
    local free_pct="$1"
    local warn_pct="$2"
    local critical_pct="$3"

    if (( free_pct <= critical_pct )); then
        printf "critical"
        return 0
    fi
    if (( free_pct <= warn_pct )); then
        printf "warn"
        return 0
    fi
    printf "ok"
}

function collect_worst_disk_usage() {
    local configured_paths="$DISK_ALERT_PATHS"
    local path df_line
    local used_pct avail_kb total_kb mount_point free_pct
    local found=0
    local worst_free=101
    local summary=""

    DISK_ALERT_CURRENT_PATH=""
    DISK_ALERT_CURRENT_MOUNT=""
    DISK_ALERT_CURRENT_FREE_PCT=100
    DISK_ALERT_CURRENT_AVAIL_KB=0
    DISK_ALERT_CURRENT_TOTAL_KB=0
    DISK_ALERT_CURRENT_USED_PCT=0
    DISK_ALERT_CURRENT_SUMMARY=""

    configured_paths="${configured_paths//,/ }"
    if [[ -z "${configured_paths//[[:space:]]/}" ]]; then
        configured_paths="/"
    fi

    for path in $configured_paths; do
        df_line="$(df -Pk -- "$path" 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5 "|" $4 "|" $2 "|" $6}')"
        if [[ -z "$df_line" ]]; then
            continue
        fi

        IFS='|' read -r used_pct avail_kb total_kb mount_point <<< "$df_line"
        if [[ ! "$used_pct" =~ ^[0-9]+$ ]] || [[ ! "$avail_kb" =~ ^[0-9]+$ ]] || [[ ! "$total_kb" =~ ^[0-9]+$ ]]; then
            continue
        fi

        free_pct=$((100 - used_pct))
        if [[ -n "$summary" ]]; then
            summary="${summary}; "
        fi
        summary="${summary}${path}:${free_pct}%"

        if (( free_pct < worst_free )); then
            found=1
            worst_free="$free_pct"
            DISK_ALERT_CURRENT_PATH="$path"
            DISK_ALERT_CURRENT_MOUNT="$mount_point"
            DISK_ALERT_CURRENT_FREE_PCT="$free_pct"
            DISK_ALERT_CURRENT_AVAIL_KB="$avail_kb"
            DISK_ALERT_CURRENT_TOTAL_KB="$total_kb"
            DISK_ALERT_CURRENT_USED_PCT="$used_pct"
        fi
    done

    DISK_ALERT_CURRENT_SUMMARY="$summary"
    if (( found == 0 )); then
        return 1
    fi
    return 0
}

function post_disk_space_alert() {
    local alert_code="$1"
    local severity="$2"
    local summary="$3"
    local previous_level="$4"
    local current_level="$5"
    local free_pct="$6"
    local monitored_path="$7"
    local mount_point="$8"
    local avail_kb="$9"
    local total_kb="${10}"
    local check_summary="${11}"
    local warn_pct="${12}"
    local critical_pct="${13}"
    local recovery_pct="${14}"
    local message_type="${15}"
    local status_value="${16}"

    if ! command -v curl >/dev/null 2>&1; then
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "curl is unavailable; skipping disk-space alert post."
        return 0
    fi

    local network station mac stream_id message_id occurred_at endpoint timeout_sec dedupe_key schema_version mount_token
    local device_json first_field payload
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
        stream_id="DISK_${host_fallback}"
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
    mount_token="$mount_point"
    if [[ -z "$mount_token" || "$mount_token" == "/" ]]; then
        mount_token="root"
    fi
    dedupe_key="disk-space.$(sanitize_token "${station:-$stream_id}").$(sanitize_token "$alert_code").$(sanitize_token "$mount_token")"

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
        device_json="${device_json}\"streamId\":\"DISK_ALERT_SENDER\""
    fi
    device_json="${device_json}}"

    payload=$(cat <<EOF
{"schemaVersion":"$(json_escape "$schema_version")","messageId":"$(json_escape "$message_id")","type":"$(json_escape "$message_type")","occurredAt":"$(json_escape "$occurred_at")","device":$device_json,"status":"$(json_escape "$status_value")","alertCode":"$(json_escape "$alert_code")","severity":"$(json_escape "$severity")","summary":"$(json_escape "$summary")","details":{"source":"sender-disk-monitor","notificationScope":"admin-only","monitoredPath":"$(json_escape "$monitored_path")","mountPoint":"$(json_escape "$mount_point")","freePercent":$free_pct,"availableKb":$avail_kb,"totalKb":$total_kb,"previousLevel":"$(json_escape "$previous_level")","currentLevel":"$(json_escape "$current_level")","warnFreePercent":$warn_pct,"criticalFreePercent":$critical_pct,"recoveryFreePercent":$recovery_pct,"diskSummary":"$(json_escape "$check_summary")","checkMode":"auto-update-timer"},"dedupeKey":"$(json_escape "$dedupe_key")"}
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
        echo "Disk-space alert ($alert_code) posted to central endpoint."
        return 0
    fi

    echo -en "[\e[1;33mWARN\e[0m] "
    echo "Failed to post disk-space alert ($alert_code) to central endpoint."
    return 0
}

function evaluate_and_post_disk_space_alert() {
    local warn_pct critical_pct recovery_pct
    local previous_level current_level next_level
    local alert_code="" severity="" summary="" message_type="device.alert" status_value="Warning"
    local checked_at

    warn_pct="$(normalize_percent_value "$DISK_ALERT_WARN_FREE_PCT" "$DISK_ALERT_WARN_FREE_PCT_DEFAULT")"
    critical_pct="$(normalize_percent_value "$DISK_ALERT_CRITICAL_FREE_PCT" "$DISK_ALERT_CRITICAL_FREE_PCT_DEFAULT")"
    recovery_pct="$(normalize_percent_value "$DISK_ALERT_RECOVERY_FREE_PCT" "$DISK_ALERT_RECOVERY_FREE_PCT_DEFAULT")"

    if (( critical_pct > warn_pct )); then
        critical_pct="$warn_pct"
    fi
    if (( recovery_pct <= warn_pct )); then
        recovery_pct=$((warn_pct + 5))
        if (( recovery_pct > 100 )); then
            recovery_pct=100
        fi
    fi

    load_disk_alert_state
    if ! collect_worst_disk_usage; then
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Disk monitor skipped: unable to read usage for paths '$DISK_ALERT_PATHS'."
        return 0
    fi

    previous_level="$DISK_ALERT_LAST_LEVEL"
    current_level="$(classify_disk_alert_level "$DISK_ALERT_CURRENT_FREE_PCT" "$warn_pct" "$critical_pct")"
    next_level="$previous_level"

    if [[ "$previous_level" == "ok" ]]; then
        if [[ "$current_level" == "critical" ]]; then
            alert_code="DISK_SPACE_CRITICAL"
            severity="critical"
            summary="Sender disk space is critically low."
            next_level="critical"
            status_value="Critical"
        elif [[ "$current_level" == "warn" ]]; then
            alert_code="DISK_SPACE_WARN"
            severity="warning"
            summary="Sender disk space is running low."
            next_level="warn"
            status_value="Warning"
        else
            next_level="ok"
        fi
    else
        if (( DISK_ALERT_CURRENT_FREE_PCT >= recovery_pct )); then
            alert_code="DISK_SPACE_RECOVERY"
            severity="info"
            summary="Sender disk space recovered above threshold."
            next_level="ok"
            message_type="device.recovery"
            status_value="Recovered"
        elif [[ "$previous_level" == "warn" && "$current_level" == "critical" ]]; then
            alert_code="DISK_SPACE_CRITICAL"
            severity="critical"
            summary="Sender disk space dropped to critical threshold."
            next_level="critical"
            status_value="Critical"
        else
            next_level="$previous_level"
        fi
    fi

    checked_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    write_disk_alert_state "$next_level" "$DISK_ALERT_CURRENT_PATH" "$DISK_ALERT_CURRENT_FREE_PCT" "$checked_at" || true

    if [[ -z "$alert_code" ]]; then
        return 0
    fi

    post_disk_space_alert \
        "$alert_code" \
        "$severity" \
        "$summary" \
        "$previous_level" \
        "$next_level" \
        "$DISK_ALERT_CURRENT_FREE_PCT" \
        "$DISK_ALERT_CURRENT_PATH" \
        "$DISK_ALERT_CURRENT_MOUNT" \
        "$DISK_ALERT_CURRENT_AVAIL_KB" \
        "$DISK_ALERT_CURRENT_TOTAL_KB" \
        "$DISK_ALERT_CURRENT_SUMMARY" \
        "$warn_pct" \
        "$critical_pct" \
        "$recovery_pct" \
        "$message_type" \
        "$status_value"
    return 0
}

function normalize_positive_int() {
    local raw="$1"
    local fallback="$2"
    local min_value="${3:-0}"

    if [[ "$raw" =~ ^[0-9]+$ ]] && (( raw >= min_value )); then
        printf "%s" "$raw"
        return 0
    fi
    printf "%s" "$fallback"
}

function is_truthy() {
    local value
    value="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]' | xargs)"
    [[ "$value" == "1" || "$value" == "true" || "$value" == "yes" || "$value" == "on" ]]
}

function resolve_watchdog_state_file_path() {
    local state_file="$WATCHDOG_STATE_FILE"
    local state_dir

    state_dir="$(dirname "$state_file")"
    if mkdir -p "$state_dir" >/dev/null 2>&1; then
        printf "%s" "$state_file"
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n mkdir -p "$state_dir" >/dev/null 2>&1; then
        printf "%s" "$state_file"
        return 0
    fi

    printf "/tmp/upri-sender/watchdog-state.env"
}

function load_watchdog_state() {
    local state_path key value

    WATCHDOG_BACKEND_STOPPED_SINCE=0
    WATCHDOG_FRONTEND_STOPPED_SINCE=0
    WATCHDOG_BACKEND_UNHEALTHY_SINCE=0
    WATCHDOG_FRONTEND_UNHEALTHY_SINCE=0
    WATCHDOG_BACKEND_LAST_RESTART_TS=0
    WATCHDOG_FRONTEND_LAST_RESTART_TS=0
    WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE=0
    WATCHDOG_TUNNEL_DISCONNECTED_SINCE=0
    WATCHDOG_TUNNEL_LAST_RESTART_TS=0

    state_path="$(resolve_watchdog_state_file_path)"
    WATCHDOG_STATE_FILE_PATH="$state_path"

    if [[ ! -r "$state_path" ]]; then
        return 0
    fi

    while IFS='=' read -r key value; do
        case "$key" in
            WATCHDOG_BACKEND_STOPPED_SINCE)
                if [[ "$value" =~ ^[0-9]+$ ]]; then WATCHDOG_BACKEND_STOPPED_SINCE="$value"; fi
                ;;
            WATCHDOG_FRONTEND_STOPPED_SINCE)
                if [[ "$value" =~ ^[0-9]+$ ]]; then WATCHDOG_FRONTEND_STOPPED_SINCE="$value"; fi
                ;;
            WATCHDOG_BACKEND_UNHEALTHY_SINCE)
                if [[ "$value" =~ ^[0-9]+$ ]]; then WATCHDOG_BACKEND_UNHEALTHY_SINCE="$value"; fi
                ;;
            WATCHDOG_FRONTEND_UNHEALTHY_SINCE)
                if [[ "$value" =~ ^[0-9]+$ ]]; then WATCHDOG_FRONTEND_UNHEALTHY_SINCE="$value"; fi
                ;;
            WATCHDOG_BACKEND_LAST_RESTART_TS)
                if [[ "$value" =~ ^[0-9]+$ ]]; then WATCHDOG_BACKEND_LAST_RESTART_TS="$value"; fi
                ;;
            WATCHDOG_FRONTEND_LAST_RESTART_TS)
                if [[ "$value" =~ ^[0-9]+$ ]]; then WATCHDOG_FRONTEND_LAST_RESTART_TS="$value"; fi
                ;;
            WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE)
                if [[ "$value" =~ ^[0-9]+$ ]]; then WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE="$value"; fi
                ;;
            WATCHDOG_TUNNEL_DISCONNECTED_SINCE)
                if [[ "$value" =~ ^[0-9]+$ ]]; then WATCHDOG_TUNNEL_DISCONNECTED_SINCE="$value"; fi
                ;;
            WATCHDOG_TUNNEL_LAST_RESTART_TS)
                if [[ "$value" =~ ^[0-9]+$ ]]; then WATCHDOG_TUNNEL_LAST_RESTART_TS="$value"; fi
                ;;
        esac
    done < "$state_path"
}

function write_watchdog_state() {
    local state_path tmp_file

    state_path="$(resolve_watchdog_state_file_path)"
    WATCHDOG_STATE_FILE_PATH="$state_path"

    tmp_file="$(mktemp "/tmp/upri-sender-watchdog-state.XXXXXX.env")" || return 1
    cat <<EOF > "$tmp_file"
WATCHDOG_BACKEND_STOPPED_SINCE=$WATCHDOG_BACKEND_STOPPED_SINCE
WATCHDOG_FRONTEND_STOPPED_SINCE=$WATCHDOG_FRONTEND_STOPPED_SINCE
WATCHDOG_BACKEND_UNHEALTHY_SINCE=$WATCHDOG_BACKEND_UNHEALTHY_SINCE
WATCHDOG_FRONTEND_UNHEALTHY_SINCE=$WATCHDOG_FRONTEND_UNHEALTHY_SINCE
WATCHDOG_BACKEND_LAST_RESTART_TS=$WATCHDOG_BACKEND_LAST_RESTART_TS
WATCHDOG_FRONTEND_LAST_RESTART_TS=$WATCHDOG_FRONTEND_LAST_RESTART_TS
WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE=$WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE
WATCHDOG_TUNNEL_DISCONNECTED_SINCE=$WATCHDOG_TUNNEL_DISCONNECTED_SINCE
WATCHDOG_TUNNEL_LAST_RESTART_TS=$WATCHDOG_TUNNEL_LAST_RESTART_TS
EOF

    if ! install_data_payload "$tmp_file" "$state_path" 0644; then
        rm -f "$tmp_file" >/dev/null 2>&1
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Failed to write watchdog state to $state_path."
        return 1
    fi

    rm -f "$tmp_file" >/dev/null 2>&1
    return 0
}

function container_exists_by_name() {
    local container_name="$1"
    docker inspect "$container_name" >/dev/null 2>&1
}

function container_running_by_name() {
    local container_name="$1"
    [[ "$(docker inspect --format='{{.State.Running}}' "$container_name" 2>/dev/null)" == "true" ]]
}

function container_health_status_by_name() {
    local container_name="$1"
    local health_status
    health_status="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_name" 2>/dev/null || true)"
    if [[ -z "$health_status" ]]; then
        printf "none"
        return 0
    fi
    printf "%s" "$health_status"
}

function ensure_container_restart_policy() {
    local container_name="$1"
    if ! container_exists_by_name "$container_name"; then
        return 0
    fi
    if docker update --restart unless-stopped "$container_name" >/dev/null 2>&1; then
        return 0
    fi
    echo -en "[\e[1;33mWARN\e[0m] "
    echo "Unable to enforce restart policy for container $container_name."
    return 1
}

function post_watchdog_alert() {
    local alert_code="$1"
    local severity="$2"
    local summary="$3"
    local message_type="$4"
    local status_value="$5"
    local container_name="$6"
    local trigger_reason="$7"
    local action_result="$8"
    local elapsed_sec="$9"
    local threshold_sec="${10}"
    local cooldown_sec="${11}"

    if ! command -v curl >/dev/null 2>&1; then
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "curl is unavailable; skipping watchdog alert post."
        return 0
    fi

    local network station mac stream_id message_id occurred_at endpoint timeout_sec dedupe_key schema_version
    local device_json first_field payload
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
        stream_id="WATCHDOG_${host_fallback}"
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
    dedupe_key="watchdog.$(sanitize_token "${station:-$stream_id}").$(sanitize_token "$container_name").$(sanitize_token "$alert_code")"

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
        device_json="${device_json}\"streamId\":\"WATCHDOG_SENDER\""
    fi
    device_json="${device_json}}"

    payload=$(cat <<EOF
{"schemaVersion":"$(json_escape "$schema_version")","messageId":"$(json_escape "$message_id")","type":"$(json_escape "$message_type")","occurredAt":"$(json_escape "$occurred_at")","device":$device_json,"status":"$(json_escape "$status_value")","alertCode":"$(json_escape "$alert_code")","severity":"$(json_escape "$severity")","summary":"$(json_escape "$summary")","details":{"source":"sender-stack-watchdog","notificationScope":"admin-only","container":"$(json_escape "$container_name")","triggerReason":"$(json_escape "$trigger_reason")","actionResult":"$(json_escape "$action_result")","elapsedSec":$elapsed_sec,"thresholdSec":$threshold_sec,"restartCooldownSec":$cooldown_sec},"dedupeKey":"$(json_escape "$dedupe_key")"}
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
        echo "Watchdog alert ($alert_code) posted for $container_name."
        return 0
    fi

    echo -en "[\e[1;33mWARN\e[0m] "
    echo "Failed to post watchdog alert ($alert_code) for $container_name."
    return 0
}

function can_attempt_watchdog_restart() {
    local last_restart_ts="$1"
    local now_epoch="$2"
    local cooldown_sec="$3"

    if (( last_restart_ts <= 0 )); then
        return 0
    fi
    if (( now_epoch - last_restart_ts >= cooldown_sec )); then
        return 0
    fi
    return 1
}

function attempt_backend_watchdog_recovery() {
    local mode="$1"
    local target_ref="${SENDER_BACKEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}"

    if [[ "$mode" == "restart" ]]; then
        stop_container >/dev/null 2>&1 || true
    fi

    if container_exists_by_name "$CONTAINER"; then
        start_container "$target_ref" >/dev/null 2>&1 || return 1
    else
        create_network >/dev/null 2>&1 || return 1
        create_container "auto" "$target_ref" >/dev/null 2>&1 || return 1
        start_container "$LAST_BACKEND_IMAGE_REF" >/dev/null 2>&1 || return 1
    fi

    ensure_container_restart_policy "$CONTAINER" >/dev/null 2>&1 || true
    return 0
}

function attempt_frontend_watchdog_recovery() {
    local mode="$1"
    local target_ref="${SENDER_FRONTEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}"

    if ! command -v sender-frontend >/dev/null 2>&1; then
        return 1
    fi

    if [[ "$mode" == "restart" ]]; then
        sender-frontend STOP >/dev/null 2>&1 || true
    fi

    if container_exists_by_name "sender-frontend"; then
        sender-frontend START >/dev/null 2>&1 || return 1
    else
        sender-frontend NETWORK_SETUP >/dev/null 2>&1 || return 1
        sender-frontend CREATE "$target_ref" >/dev/null 2>&1 || return 1
        sender-frontend START >/dev/null 2>&1 || return 1
    fi

    ensure_container_restart_policy "sender-frontend" >/dev/null 2>&1 || true
    return 0
}

function reset_remote_tunnel_watchdog_state() {
    WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE=0
    WATCHDOG_TUNNEL_DISCONNECTED_SINCE=0
}

function remote_tunnel_watchdog_connected_state() {
    local state_path
    local state_body

    state_path="$(resolve_remote_tunnel_state_file_path)"
    REMOTE_TUNNEL_STATE_FILE_PATH="$state_path"
    if [[ ! -r "$state_path" ]]; then
        printf "unknown"
        return 0
    fi

    state_body="$(tr -d '\r\n' < "$state_path" 2>/dev/null || true)"
    if [[ "$state_body" =~ \"connected\"[[:space:]]*:[[:space:]]*true ]]; then
        printf "true"
        return 0
    fi
    if [[ "$state_body" =~ \"connected\"[[:space:]]*:[[:space:]]*false ]]; then
        printf "false"
        return 0
    fi

    printf "unknown"
    return 0
}

function attempt_remote_tunnel_watchdog_recovery() {
    local pid=""

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl restart "$REMOTE_TUNNEL_SERVICE" >/dev/null 2>&1; then
            return 0
        fi
        if command -v sudo >/dev/null 2>&1 && sudo -n systemctl restart "$REMOTE_TUNNEL_SERVICE" >/dev/null 2>&1; then
            return 0
        fi
    fi

    if [[ -r "$REMOTE_TUNNEL_PID_FILE" ]]; then
        pid="$(head -n 1 "$REMOTE_TUNNEL_PID_FILE" | tr -d '\r' | xargs)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" >/dev/null 2>&1; then
            if kill "$pid" >/dev/null 2>&1; then
                return 0
            fi
        fi
    fi

    return 1
}

function evaluate_remote_tunnel_watchdog() {
    local now_epoch="$1"
    local service_down_threshold_sec="$2"
    local disconnected_threshold_sec="$3"
    local restart_cooldown_sec="$4"
    local active_state
    local connected_state
    local elapsed
    local component_name="$REMOTE_TUNNEL_SERVICE"

    if ! is_truthy "$WATCHDOG_REMOTE_TUNNEL_ENABLED"; then
        reset_remote_tunnel_watchdog_state
        return 0
    fi

    load_remote_tunnel_env
    if ! is_truthy "$REMOTE_TUNNEL_ENABLED_VALUE"; then
        reset_remote_tunnel_watchdog_state
        return 0
    fi
    if ! remote_tunnel_config_is_complete; then
        reset_remote_tunnel_watchdog_state
        return 0
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        reset_remote_tunnel_watchdog_state
        return 0
    fi

    active_state="$(systemctl is-active "$REMOTE_TUNNEL_SERVICE" 2>/dev/null || true)"
    if [[ -z "$active_state" ]]; then
        reset_remote_tunnel_watchdog_state
        return 0
    fi

    if [[ "$active_state" != "active" ]]; then
        if (( WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE == 0 )); then
            WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE="$now_epoch"
            WATCHDOG_TUNNEL_DISCONNECTED_SINCE=0
            return 0
        fi

        elapsed=$((now_epoch - WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE))
        if (( elapsed < service_down_threshold_sec )); then
            return 0
        fi
        if ! can_attempt_watchdog_restart "$WATCHDOG_TUNNEL_LAST_RESTART_TS" "$now_epoch" "$restart_cooldown_sec"; then
            return 0
        fi

        if attempt_remote_tunnel_watchdog_recovery; then
            post_watchdog_alert "WATCHDOG_TUNNEL_RECOVERED" "info" "Watchdog restarted sender remote tunnel service." "device.recovery" "Recovered" "$component_name" "service-inactive" "restart-success" "$elapsed" "$service_down_threshold_sec" "$restart_cooldown_sec"
            reset_remote_tunnel_watchdog_state
        else
            post_watchdog_alert "WATCHDOG_TUNNEL_RECOVERY_FAILED" "warning" "Watchdog failed to restart sender remote tunnel service." "device.alert" "Error" "$component_name" "service-inactive" "restart-failed" "$elapsed" "$service_down_threshold_sec" "$restart_cooldown_sec"
        fi
        WATCHDOG_TUNNEL_LAST_RESTART_TS="$now_epoch"
        return 0
    fi

    WATCHDOG_TUNNEL_SERVICE_DOWN_SINCE=0
    connected_state="$(remote_tunnel_watchdog_connected_state)"
    if [[ "$connected_state" == "unknown" ]]; then
        WATCHDOG_TUNNEL_DISCONNECTED_SINCE=0
        return 0
    fi
    if [[ "$connected_state" == "true" ]]; then
        WATCHDOG_TUNNEL_DISCONNECTED_SINCE=0
        return 0
    fi

    if (( WATCHDOG_TUNNEL_DISCONNECTED_SINCE == 0 )); then
        WATCHDOG_TUNNEL_DISCONNECTED_SINCE="$now_epoch"
        return 0
    fi

    elapsed=$((now_epoch - WATCHDOG_TUNNEL_DISCONNECTED_SINCE))
    if (( elapsed < disconnected_threshold_sec )); then
        return 0
    fi
    if ! can_attempt_watchdog_restart "$WATCHDOG_TUNNEL_LAST_RESTART_TS" "$now_epoch" "$restart_cooldown_sec"; then
        return 0
    fi

    if attempt_remote_tunnel_watchdog_recovery; then
        post_watchdog_alert "WATCHDOG_TUNNEL_RECOVERED" "info" "Watchdog restarted disconnected sender remote tunnel service." "device.recovery" "Recovered" "$component_name" "tunnel-disconnected" "restart-success" "$elapsed" "$disconnected_threshold_sec" "$restart_cooldown_sec"
        reset_remote_tunnel_watchdog_state
    else
        post_watchdog_alert "WATCHDOG_TUNNEL_RECOVERY_FAILED" "warning" "Watchdog failed to restart disconnected sender remote tunnel service." "device.alert" "Error" "$component_name" "tunnel-disconnected" "restart-failed" "$elapsed" "$disconnected_threshold_sec" "$restart_cooldown_sec"
    fi
    WATCHDOG_TUNNEL_LAST_RESTART_TS="$now_epoch"
    return 0
}

function evaluate_backend_watchdog() {
    local now_epoch="$1"
    local stopped_threshold_sec="$2"
    local unhealthy_threshold_sec="$3"
    local restart_cooldown_sec="$4"
    local elapsed
    local health_status

    if ! container_exists_by_name "$CONTAINER"; then
        if (( WATCHDOG_BACKEND_STOPPED_SINCE == 0 )); then
            WATCHDOG_BACKEND_STOPPED_SINCE="$now_epoch"
            return 0
        fi
        elapsed=$((now_epoch - WATCHDOG_BACKEND_STOPPED_SINCE))
        if (( elapsed < stopped_threshold_sec )); then
            return 0
        fi
        if ! can_attempt_watchdog_restart "$WATCHDOG_BACKEND_LAST_RESTART_TS" "$now_epoch" "$restart_cooldown_sec"; then
            return 0
        fi
        if attempt_backend_watchdog_recovery "start"; then
            post_watchdog_alert "WATCHDOG_CONTAINER_RESTARTED" "info" "Watchdog restarted sender-backend container." "device.recovery" "Recovered" "$CONTAINER" "missing" "start-success" "$elapsed" "$stopped_threshold_sec" "$restart_cooldown_sec"
            WATCHDOG_BACKEND_STOPPED_SINCE=0
            WATCHDOG_BACKEND_UNHEALTHY_SINCE=0
        else
            post_watchdog_alert "WATCHDOG_CONTAINER_RESTART_FAILED" "warning" "Watchdog failed to restart sender-backend container." "device.alert" "Error" "$CONTAINER" "missing" "start-failed" "$elapsed" "$stopped_threshold_sec" "$restart_cooldown_sec"
        fi
        WATCHDOG_BACKEND_LAST_RESTART_TS="$now_epoch"
        return 0
    fi

    ensure_container_restart_policy "$CONTAINER" >/dev/null 2>&1 || true

    if ! container_running_by_name "$CONTAINER"; then
        if (( WATCHDOG_BACKEND_STOPPED_SINCE == 0 )); then
            WATCHDOG_BACKEND_STOPPED_SINCE="$now_epoch"
            return 0
        fi
        elapsed=$((now_epoch - WATCHDOG_BACKEND_STOPPED_SINCE))
        if (( elapsed < stopped_threshold_sec )); then
            return 0
        fi
        if ! can_attempt_watchdog_restart "$WATCHDOG_BACKEND_LAST_RESTART_TS" "$now_epoch" "$restart_cooldown_sec"; then
            return 0
        fi
        if attempt_backend_watchdog_recovery "start"; then
            post_watchdog_alert "WATCHDOG_CONTAINER_RESTARTED" "info" "Watchdog started stopped sender-backend container." "device.recovery" "Recovered" "$CONTAINER" "stopped" "start-success" "$elapsed" "$stopped_threshold_sec" "$restart_cooldown_sec"
            WATCHDOG_BACKEND_STOPPED_SINCE=0
            WATCHDOG_BACKEND_UNHEALTHY_SINCE=0
        else
            post_watchdog_alert "WATCHDOG_CONTAINER_RESTART_FAILED" "warning" "Watchdog failed to start stopped sender-backend container." "device.alert" "Error" "$CONTAINER" "stopped" "start-failed" "$elapsed" "$stopped_threshold_sec" "$restart_cooldown_sec"
        fi
        WATCHDOG_BACKEND_LAST_RESTART_TS="$now_epoch"
        return 0
    fi

    WATCHDOG_BACKEND_STOPPED_SINCE=0
    health_status="$(container_health_status_by_name "$CONTAINER")"
    if [[ "$health_status" != "unhealthy" ]]; then
        WATCHDOG_BACKEND_UNHEALTHY_SINCE=0
        return 0
    fi

    if (( WATCHDOG_BACKEND_UNHEALTHY_SINCE == 0 )); then
        WATCHDOG_BACKEND_UNHEALTHY_SINCE="$now_epoch"
        return 0
    fi
    elapsed=$((now_epoch - WATCHDOG_BACKEND_UNHEALTHY_SINCE))
    if (( elapsed < unhealthy_threshold_sec )); then
        return 0
    fi
    if ! can_attempt_watchdog_restart "$WATCHDOG_BACKEND_LAST_RESTART_TS" "$now_epoch" "$restart_cooldown_sec"; then
        return 0
    fi
    if attempt_backend_watchdog_recovery "restart"; then
        post_watchdog_alert "WATCHDOG_CONTAINER_RESTARTED" "info" "Watchdog restarted unhealthy sender-backend container." "device.recovery" "Recovered" "$CONTAINER" "unhealthy" "restart-success" "$elapsed" "$unhealthy_threshold_sec" "$restart_cooldown_sec"
        WATCHDOG_BACKEND_UNHEALTHY_SINCE=0
    else
        post_watchdog_alert "WATCHDOG_CONTAINER_RESTART_FAILED" "warning" "Watchdog failed to restart unhealthy sender-backend container." "device.alert" "Error" "$CONTAINER" "unhealthy" "restart-failed" "$elapsed" "$unhealthy_threshold_sec" "$restart_cooldown_sec"
    fi
    WATCHDOG_BACKEND_LAST_RESTART_TS="$now_epoch"
    return 0
}

function evaluate_frontend_watchdog() {
    local now_epoch="$1"
    local stopped_threshold_sec="$2"
    local unhealthy_threshold_sec="$3"
    local restart_cooldown_sec="$4"
    local elapsed
    local health_status
    local container_name="sender-frontend"

    if ! container_exists_by_name "$container_name"; then
        if (( WATCHDOG_FRONTEND_STOPPED_SINCE == 0 )); then
            WATCHDOG_FRONTEND_STOPPED_SINCE="$now_epoch"
            return 0
        fi
        elapsed=$((now_epoch - WATCHDOG_FRONTEND_STOPPED_SINCE))
        if (( elapsed < stopped_threshold_sec )); then
            return 0
        fi
        if ! can_attempt_watchdog_restart "$WATCHDOG_FRONTEND_LAST_RESTART_TS" "$now_epoch" "$restart_cooldown_sec"; then
            return 0
        fi
        if attempt_frontend_watchdog_recovery "start"; then
            post_watchdog_alert "WATCHDOG_CONTAINER_RESTARTED" "info" "Watchdog restarted sender-frontend container." "device.recovery" "Recovered" "$container_name" "missing" "start-success" "$elapsed" "$stopped_threshold_sec" "$restart_cooldown_sec"
            WATCHDOG_FRONTEND_STOPPED_SINCE=0
            WATCHDOG_FRONTEND_UNHEALTHY_SINCE=0
        else
            post_watchdog_alert "WATCHDOG_CONTAINER_RESTART_FAILED" "warning" "Watchdog failed to restart sender-frontend container." "device.alert" "Error" "$container_name" "missing" "start-failed" "$elapsed" "$stopped_threshold_sec" "$restart_cooldown_sec"
        fi
        WATCHDOG_FRONTEND_LAST_RESTART_TS="$now_epoch"
        return 0
    fi

    ensure_container_restart_policy "$container_name" >/dev/null 2>&1 || true

    if ! container_running_by_name "$container_name"; then
        if (( WATCHDOG_FRONTEND_STOPPED_SINCE == 0 )); then
            WATCHDOG_FRONTEND_STOPPED_SINCE="$now_epoch"
            return 0
        fi
        elapsed=$((now_epoch - WATCHDOG_FRONTEND_STOPPED_SINCE))
        if (( elapsed < stopped_threshold_sec )); then
            return 0
        fi
        if ! can_attempt_watchdog_restart "$WATCHDOG_FRONTEND_LAST_RESTART_TS" "$now_epoch" "$restart_cooldown_sec"; then
            return 0
        fi
        if attempt_frontend_watchdog_recovery "start"; then
            post_watchdog_alert "WATCHDOG_CONTAINER_RESTARTED" "info" "Watchdog started stopped sender-frontend container." "device.recovery" "Recovered" "$container_name" "stopped" "start-success" "$elapsed" "$stopped_threshold_sec" "$restart_cooldown_sec"
            WATCHDOG_FRONTEND_STOPPED_SINCE=0
            WATCHDOG_FRONTEND_UNHEALTHY_SINCE=0
        else
            post_watchdog_alert "WATCHDOG_CONTAINER_RESTART_FAILED" "warning" "Watchdog failed to start stopped sender-frontend container." "device.alert" "Error" "$container_name" "stopped" "start-failed" "$elapsed" "$stopped_threshold_sec" "$restart_cooldown_sec"
        fi
        WATCHDOG_FRONTEND_LAST_RESTART_TS="$now_epoch"
        return 0
    fi

    WATCHDOG_FRONTEND_STOPPED_SINCE=0
    health_status="$(container_health_status_by_name "$container_name")"
    if [[ "$health_status" != "unhealthy" ]]; then
        WATCHDOG_FRONTEND_UNHEALTHY_SINCE=0
        return 0
    fi

    if (( WATCHDOG_FRONTEND_UNHEALTHY_SINCE == 0 )); then
        WATCHDOG_FRONTEND_UNHEALTHY_SINCE="$now_epoch"
        return 0
    fi
    elapsed=$((now_epoch - WATCHDOG_FRONTEND_UNHEALTHY_SINCE))
    if (( elapsed < unhealthy_threshold_sec )); then
        return 0
    fi
    if ! can_attempt_watchdog_restart "$WATCHDOG_FRONTEND_LAST_RESTART_TS" "$now_epoch" "$restart_cooldown_sec"; then
        return 0
    fi
    if attempt_frontend_watchdog_recovery "restart"; then
        post_watchdog_alert "WATCHDOG_CONTAINER_RESTARTED" "info" "Watchdog restarted unhealthy sender-frontend container." "device.recovery" "Recovered" "$container_name" "unhealthy" "restart-success" "$elapsed" "$unhealthy_threshold_sec" "$restart_cooldown_sec"
        WATCHDOG_FRONTEND_UNHEALTHY_SINCE=0
    else
        post_watchdog_alert "WATCHDOG_CONTAINER_RESTART_FAILED" "warning" "Watchdog failed to restart unhealthy sender-frontend container." "device.alert" "Error" "$container_name" "unhealthy" "restart-failed" "$elapsed" "$unhealthy_threshold_sec" "$restart_cooldown_sec"
    fi
    WATCHDOG_FRONTEND_LAST_RESTART_TS="$now_epoch"
    return 0
}

function watchdog_check() {
    local now_epoch
    local stopped_backend_threshold
    local stopped_frontend_threshold
    local unhealthy_backend_threshold
    local unhealthy_frontend_threshold
    local tunnel_service_down_threshold
    local tunnel_disconnected_threshold
    local restart_cooldown_sec

    if ! is_truthy "$WATCHDOG_ENABLED"; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Watchdog is disabled (WATCHDOG_ENABLED=$WATCHDOG_ENABLED)."
        return 0
    fi

    stopped_backend_threshold="$(normalize_positive_int "$WATCHDOG_BACKEND_STOPPED_MAX_SEC" "$WATCHDOG_BACKEND_STOPPED_MAX_SEC_DEFAULT" 30)"
    stopped_frontend_threshold="$(normalize_positive_int "$WATCHDOG_FRONTEND_STOPPED_MAX_SEC" "$WATCHDOG_FRONTEND_STOPPED_MAX_SEC_DEFAULT" 30)"
    unhealthy_backend_threshold="$(normalize_positive_int "$WATCHDOG_BACKEND_UNHEALTHY_MAX_SEC" "$WATCHDOG_BACKEND_UNHEALTHY_MAX_SEC_DEFAULT" 30)"
    unhealthy_frontend_threshold="$(normalize_positive_int "$WATCHDOG_FRONTEND_UNHEALTHY_MAX_SEC" "$WATCHDOG_FRONTEND_UNHEALTHY_MAX_SEC_DEFAULT" 30)"
    tunnel_service_down_threshold="$(normalize_positive_int "$WATCHDOG_REMOTE_TUNNEL_SERVICE_DOWN_MAX_SEC" "$WATCHDOG_REMOTE_TUNNEL_SERVICE_DOWN_MAX_SEC_DEFAULT" 30)"
    tunnel_disconnected_threshold="$(normalize_positive_int "$WATCHDOG_REMOTE_TUNNEL_DISCONNECTED_MAX_SEC" "$WATCHDOG_REMOTE_TUNNEL_DISCONNECTED_MAX_SEC_DEFAULT" 30)"
    restart_cooldown_sec="$(normalize_positive_int "$WATCHDOG_RESTART_COOLDOWN_SEC" "$WATCHDOG_RESTART_COOLDOWN_SEC_DEFAULT" 30)"

    now_epoch="$(date +%s)"
    load_watchdog_state
    evaluate_backend_watchdog "$now_epoch" "$stopped_backend_threshold" "$unhealthy_backend_threshold" "$restart_cooldown_sec"
    evaluate_frontend_watchdog "$now_epoch" "$stopped_frontend_threshold" "$unhealthy_frontend_threshold" "$restart_cooldown_sec"
    evaluate_remote_tunnel_watchdog "$now_epoch" "$tunnel_service_down_threshold" "$tunnel_disconnected_threshold" "$restart_cooldown_sec"
    write_watchdog_state || true
    return 0
}

function run_with_maintenance_lock() {
    local mode="$1"
    local wait_sec="$2"
    shift 2

    if ! command -v flock >/dev/null 2>&1; then
        "$@"
        return $?
    fi

    mkdir -p "$(dirname "$WATCHDOG_LOCK_FILE")" >/dev/null 2>&1 || true
    exec {lock_fd}> "$WATCHDOG_LOCK_FILE" || {
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Unable to open maintenance lock file $WATCHDOG_LOCK_FILE; running without lock."
        "$@"
        return $?
    }

    if [[ "$mode" == "wait" ]]; then
        if ! flock -w "$wait_sec" "$lock_fd"; then
            echo -en "[\e[1;33mWARN\e[0m] "
            echo "Could not acquire maintenance lock within ${wait_sec}s."
            eval "exec ${lock_fd}>&-"
            return 1
        fi
    else
        if ! flock -n "$lock_fd"; then
            echo -en "[\e[1;33mWARN\e[0m] "
            echo "Maintenance lock is busy; skipping operation."
            eval "exec ${lock_fd}>&-"
            return 0
        fi
    fi

    "$@"
    local cmd_exit=$?
    flock -u "$lock_fd" >/dev/null 2>&1 || true
    eval "exec ${lock_fd}>&-"
    return $cmd_exit
}

function run_update_stack_with_lock() {
    run_with_maintenance_lock "wait" 1800 update_stack_with_alert
}

function run_watchdog_check_with_lock() {
    run_with_maintenance_lock "skip" 0 watchdog_check
}

function warn_deprecated_script_update_envs() {
    local warned=0

    if [[ -n "${SENDER_SCRIPT_AUTO_UPDATE_ENABLED:-}" ]]; then
        warned=1
    fi
    if [[ -n "${SENDER_BACKEND_SCRIPT_URL:-}" ]]; then
        warned=1
    fi
    if [[ -n "${SENDER_FRONTEND_SCRIPT_URL:-}" ]]; then
        warned=1
    fi

    if [[ $warned -eq 1 ]]; then
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Legacy URL-based host script auto-update env vars are deprecated and ignored."
    fi
}

function refresh_sender_scripts() {
    SCRIPT_BACKEND_UPDATE_STATE="deprecated-ignored"
    SCRIPT_FRONTEND_UPDATE_STATE="deprecated-ignored"
    LAST_SCRIPT_SYNC_RESULT="managed-by-startup-hook"
    warn_deprecated_script_update_envs
    return 0
}

function write_update_state_files() {
    local backend_result="$1"
    local frontend_result="$2"
    local backend_exit="$3"
    local frontend_exit="$4"
    local backend_pull_state="$5"
    local frontend_pull_state="$6"
    local backend_ref="$7"
    local frontend_ref="$8"
    local backend_digest="$9"
    local frontend_digest="${10}"
    local bundle_tag="${11}"
    local backend_bundle_version="${12}"
    local frontend_bundle_version="${13}"
    local script_sync_result="${14}"
    local alert_post_result="${15}"
    local now_iso now_epoch state_path tmp_file

    now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    now_epoch="$(date +%s)"
    state_path="$(resolve_state_file_path)"
    LAST_STATE_FILE_PATH="$state_path"

    tmp_file="$(mktemp "/tmp/upri-sender-state.XXXXXX.json")" || return 1
    cat <<EOF > "$tmp_file"
{"timestamp":"$(json_escape "$now_iso")","bundleTag":"$(json_escape "$bundle_tag")","backendDigest":"$(json_escape "$backend_digest")","frontendDigest":"$(json_escape "$frontend_digest")","backendResult":"$(json_escape "$backend_result")","frontendResult":"$(json_escape "$frontend_result")","scriptSyncResult":"$(json_escape "$script_sync_result")","alertPostResult":"$(json_escape "$alert_post_result")","rollback":{"result":"$(json_escape "$LAST_ROLLBACK_RESULT")","backendExitCode":$LAST_ROLLBACK_BACKEND_EXIT,"frontendExitCode":$LAST_ROLLBACK_FRONTEND_EXIT,"backendTarget":"$(json_escape "$LAST_ROLLBACK_BACKEND_TARGET")","frontendTarget":"$(json_escape "$LAST_ROLLBACK_FRONTEND_TARGET")"},"migration":{"result":"$(json_escape "$LAST_MIGRATION_RESULT")","summary":"$(json_escape "$LAST_MIGRATION_SUMMARY")","changed":"$(json_escape "$LAST_MIGRATION_CHANGED")","backendEnv":"$(json_escape "$LAST_MIGRATION_BACKEND_ENV_RESULT")","remoteTunnelEnv":"$(json_escape "$LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT")","remoteTunnelService":"$(json_escape "$LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT")","nextStep":"$(json_escape "$LAST_MIGRATION_NEXT_STEP")","remaining":"$(json_escape "$LAST_MIGRATION_REMAINING")"},"backend":{"exitCode":$backend_exit,"pullState":"$(json_escape "$backend_pull_state")","imageRef":"$(json_escape "$backend_ref")","bundleVersion":"$(json_escape "$backend_bundle_version")"},"frontend":{"exitCode":$frontend_exit,"pullState":"$(json_escape "$frontend_pull_state")","imageRef":"$(json_escape "$frontend_ref")","bundleVersion":"$(json_escape "$frontend_bundle_version")"}}
EOF

    if install_data_payload "$tmp_file" "$state_path" 0644; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Auto-update state written to $state_path."
    else
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "Failed to write auto-update state to $state_path."
    fi
    rm -f "$tmp_file" >/dev/null 2>&1

    cat <<EOF > "$LEGACY_AUTO_UPDATE_STATE_FILE"
BACKEND_EXIT=$backend_exit
BACKEND_PULL_STATE=$backend_pull_state
BACKEND_SCRIPT_UPDATE_STATE=$SCRIPT_BACKEND_UPDATE_STATE
FRONTEND_SCRIPT_UPDATE_STATE=$SCRIPT_FRONTEND_UPDATE_STATE
BACKEND_IMAGE=$backend_ref
BACKEND_CONTAINER=$CONTAINER
BACKEND_DIGEST=$backend_digest
FRONTEND_DIGEST=$frontend_digest
BUNDLE_TAG=$bundle_tag
BACKEND_BUNDLE_VERSION=$backend_bundle_version
FRONTEND_BUNDLE_VERSION=$frontend_bundle_version
ROLLBACK_RESULT=$LAST_ROLLBACK_RESULT
ROLLBACK_BACKEND_EXIT=$LAST_ROLLBACK_BACKEND_EXIT
ROLLBACK_FRONTEND_EXIT=$LAST_ROLLBACK_FRONTEND_EXIT
ROLLBACK_BACKEND_TARGET=$LAST_ROLLBACK_BACKEND_TARGET
ROLLBACK_FRONTEND_TARGET=$LAST_ROLLBACK_FRONTEND_TARGET
STATE_TS=$now_epoch
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
    local backend_image_ref="${10}"
    local frontend_image_ref="${11}"
    local backend_digest="${12}"
    local frontend_digest="${13}"
    local bundle_tag="${14}"
    local backend_bundle_version="${15}"
    local frontend_bundle_version="${16}"
    local script_sync_result="${17}"

    if ! command -v curl >/dev/null 2>&1; then
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "curl is unavailable; skipping auto-update alert post."
        LAST_ALERT_POST_RESULT="skipped-no-curl"
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
{"schemaVersion":"$(json_escape "$schema_version")","messageId":"$(json_escape "$message_id")","type":"device.alert","occurredAt":"$(json_escape "$occurred_at")","device":$device_json,"status":"AUTO_UPDATE","alertCode":"$(json_escape "$alert_code")","severity":"$(json_escape "$severity")","summary":"$(json_escape "$summary")","details":{"source":"sender-stack-auto-update","notificationScope":"admin-only","backendExitCode":$backend_exit,"frontendExitCode":$frontend_exit,"backendPullState":"$(json_escape "$backend_pull_state")","frontendPullState":"$(json_escape "$frontend_pull_state")","backendScriptUpdate":"$(json_escape "$backend_script_update")","frontendScriptUpdate":"$(json_escape "$frontend_script_update")","bundleTag":"$(json_escape "$bundle_tag")","bundleVersion":"$(json_escape "$backend_bundle_version")","frontendBundleVersion":"$(json_escape "$frontend_bundle_version")","backendImageRef":"$(json_escape "$backend_image_ref")","frontendImageRef":"$(json_escape "$frontend_image_ref")","backendDigest":"$(json_escape "$backend_digest")","frontendDigest":"$(json_escape "$frontend_digest")","scriptSyncResult":"$(json_escape "$script_sync_result")","rollbackResult":"$(json_escape "$LAST_ROLLBACK_RESULT")","rollbackBackendExitCode":$LAST_ROLLBACK_BACKEND_EXIT,"rollbackFrontendExitCode":$LAST_ROLLBACK_FRONTEND_EXIT,"rollbackBackendTarget":"$(json_escape "$LAST_ROLLBACK_BACKEND_TARGET")","rollbackFrontendTarget":"$(json_escape "$LAST_ROLLBACK_FRONTEND_TARGET")","migrationResult":"$(json_escape "$LAST_MIGRATION_RESULT")","migrationChanged":"$(json_escape "$LAST_MIGRATION_CHANGED")","migrationSummary":"$(json_escape "$LAST_MIGRATION_SUMMARY")","migrationBackendEnv":"$(json_escape "$LAST_MIGRATION_BACKEND_ENV_RESULT")","migrationRemoteTunnelEnv":"$(json_escape "$LAST_MIGRATION_REMOTE_TUNNEL_ENV_RESULT")","migrationRemoteTunnelService":"$(json_escape "$LAST_MIGRATION_REMOTE_TUNNEL_SERVICE_RESULT")","migrationNextStep":"$(json_escape "$LAST_MIGRATION_NEXT_STEP")","migrationRemaining":"$(json_escape "$LAST_MIGRATION_REMAINING")"},"dedupeKey":"$(json_escape "$dedupe_key")"}
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
        LAST_ALERT_POST_RESULT="success"
        return 0
    fi

    echo -en "[\e[1;33mWARN\e[0m] "
    echo "Failed to post auto-update alert to central endpoint."
    LAST_ALERT_POST_RESULT="failed"
    return 0
}

function resolve_bundle_targets() {
    local backend_tag_ref frontend_tag_ref
    local backend_resolved frontend_resolved
    local backend_version frontend_version

    backend_tag_ref="${SENDER_BACKEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}"
    frontend_tag_ref="${SENDER_FRONTEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}"

    LAST_PULL_RESULT="unknown"
    backend_resolved="$(resolve_image_ref "$backend_tag_ref")" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to resolve backend image ref for $backend_tag_ref."
        return 1
    }

    LAST_PULL_RESULT="unknown"
    frontend_resolved="$(resolve_image_ref "$frontend_tag_ref")" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to resolve frontend image ref for $frontend_tag_ref."
        return 1
    }

    backend_version="$(get_image_label "$backend_resolved" "org.upri.sender.bundle.version")"
    frontend_version="$(get_image_label "$frontend_resolved" "org.upri.sender.bundle.version")"

    if [[ -n "$backend_version" && -n "$frontend_version" && "$backend_version" != "$frontend_version" ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Bundle version mismatch: backend=$backend_version frontend=$frontend_version."
        return 1
    fi

    LAST_BACKEND_IMAGE_REF="$backend_tag_ref"
    LAST_FRONTEND_IMAGE_REF="$frontend_tag_ref"
    LAST_BACKEND_DIGEST="${backend_resolved##*@}"
    LAST_FRONTEND_DIGEST="${frontend_resolved##*@}"
    LAST_BUNDLE_VERSION="${backend_version:-unknown}"
    LAST_FRONTEND_BUNDLE_VERSION="${frontend_version:-$LAST_BUNDLE_VERSION}"

    return 0
}

function ensure_host_scripts_dir() {
    if mkdir -p "$SENDER_HOST_SCRIPTS_DIR" >/dev/null 2>&1; then
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n mkdir -p "$SENDER_HOST_SCRIPTS_DIR" >/dev/null 2>&1; then
        return 0
    fi
    echo -en "[\e[1;33mWARN\e[0m] "
    echo "Unable to ensure host scripts directory $SENDER_HOST_SCRIPTS_DIR."
    return 1
}

function write_alert_runtime_env_template_if_missing() {
    local env_file="${ALERT_RUNTIME_ENV_FILE:-$ALERT_RUNTIME_ENV_FILE_DEFAULT}"
    local env_dir
    local tmp_file

    ALERT_RUNTIME_ENV_FILE="$env_file"
    if [[ -f "$env_file" ]]; then
        return 0
    fi

    env_dir="$(dirname "$env_file")"
    if ! mkdir -p "$env_dir" >/dev/null 2>&1; then
        if ! (command -v sudo >/dev/null 2>&1 && sudo -n mkdir -p "$env_dir" >/dev/null 2>&1); then
            echo -en "[\e[1;33mWARN\e[0m] "
            echo "Unable to create alert runtime env directory: $env_dir"
            return 1
        fi
    fi

    tmp_file="$(mktemp "/tmp/upri-sender-alert-env.XXXXXX")" || return 1
    cat <<EOF > "$tmp_file"
# Managed by sender-backend. Used for authenticated RShake alert posts.
RSHAKE_ALERT_SHARED_SECRET=
RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT=
EOF

    if install_data_payload "$tmp_file" "$env_file" 0600; then
        rm -f "$tmp_file" >/dev/null 2>&1
        return 0
    fi

    rm -f "$tmp_file" >/dev/null 2>&1
    echo -en "[\e[1;33mWARN\e[0m] "
    echo "Unable to write alert runtime env template at $env_file."
    return 1
}

function attempt_auto_update_rollback() {
    local backend_previous_ref="$1"
    local frontend_previous_ref="$2"
    local target_backend_ref="$3"
    local target_frontend_ref="$4"
    local should_rollback_backend=0
    local should_rollback_frontend=0
    local backend_output frontend_output

    LAST_ROLLBACK_RESULT="not-needed"
    LAST_ROLLBACK_BACKEND_EXIT=0
    LAST_ROLLBACK_FRONTEND_EXIT=0
    LAST_ROLLBACK_BACKEND_TARGET="none"
    LAST_ROLLBACK_FRONTEND_TARGET="none"

    if ! is_truthy "$AUTO_UPDATE_ROLLBACK_ENABLED"; then
        LAST_ROLLBACK_RESULT="disabled"
        return 0
    fi

    if [[ -n "$backend_previous_ref" && "$backend_previous_ref" != "$target_backend_ref" ]]; then
        should_rollback_backend=1
        LAST_ROLLBACK_BACKEND_TARGET="$backend_previous_ref"
    fi
    if [[ -n "$frontend_previous_ref" && "$frontend_previous_ref" != "$target_frontend_ref" ]]; then
        should_rollback_frontend=1
        LAST_ROLLBACK_FRONTEND_TARGET="$frontend_previous_ref"
    fi

    if [[ $should_rollback_backend -eq 0 && $should_rollback_frontend -eq 0 ]]; then
        LAST_ROLLBACK_RESULT="not-needed"
        return 0
    fi

    LAST_ROLLBACK_RESULT="in-progress"

    if [[ $should_rollback_backend -eq 1 ]]; then
        backend_output="$(update_container "$backend_previous_ref" 2>&1)"
        LAST_ROLLBACK_BACKEND_EXIT=$?
        if [[ -n "$backend_output" ]]; then
            echo "$backend_output"
        fi
    fi

    if [[ $should_rollback_frontend -eq 1 ]]; then
        if [[ -x /usr/local/bin/sender-frontend ]]; then
            frontend_output="$(/usr/local/bin/sender-frontend UPDATE "$frontend_previous_ref" 2>&1)"
            LAST_ROLLBACK_FRONTEND_EXIT=$?
            if [[ -n "$frontend_output" ]]; then
                echo "$frontend_output"
            fi
        else
            LAST_ROLLBACK_FRONTEND_EXIT=127
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "sender-frontend script is missing; cannot rollback frontend."
        fi
    fi

    if [[ $LAST_ROLLBACK_BACKEND_EXIT -eq 0 && $LAST_ROLLBACK_FRONTEND_EXIT -eq 0 ]]; then
        LAST_ROLLBACK_RESULT="success"
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Rollback completed successfully."
        return 0
    fi

    LAST_ROLLBACK_RESULT="failed"
    echo -en "[\e[1;31mFAILED\e[0m] "
    echo "Rollback failed (backendExit=$LAST_ROLLBACK_BACKEND_EXIT frontendExit=$LAST_ROLLBACK_FRONTEND_EXIT)."
    return 1
}

function update_stack_with_alert() {
    local backend_output backend_exit frontend_output frontend_exit
    local backend_pull_state frontend_pull_state
    local backend_result frontend_result
    local backend_current_digest frontend_current_digest
    local backend_previous_ref frontend_previous_ref
    local target_backend_ref target_frontend_ref
    local target_backend_digest target_frontend_digest
    local target_backend_version target_frontend_version
    local alert_code severity summary
    local backend_was_stale=0
    local tunnel_was_stale=0

    LAST_ROLLBACK_RESULT="not-needed"
    LAST_ROLLBACK_BACKEND_EXIT=0
    LAST_ROLLBACK_FRONTEND_EXIT=0
    LAST_ROLLBACK_BACKEND_TARGET="none"
    LAST_ROLLBACK_FRONTEND_TARGET="none"
    reset_auto_update_migration_state

    rm -f "$LEGACY_AUTO_UPDATE_STATE_FILE" >/dev/null 2>&1 || true
    refresh_sender_scripts
    ensure_host_scripts_dir || true
    if backend_container_has_legacy_domain_quiet; then
        backend_was_stale=1
    fi
    if remote_tunnel_env_has_legacy_domain; then
        tunnel_was_stale=1
    fi

    if ! resolve_bundle_targets; then
        target_backend_ref="$LAST_BACKEND_IMAGE_REF"
        target_frontend_ref="$LAST_FRONTEND_IMAGE_REF"
        target_backend_digest="$LAST_BACKEND_DIGEST"
        target_frontend_digest="$LAST_FRONTEND_DIGEST"
        target_backend_version="$LAST_BUNDLE_VERSION"
        target_frontend_version="$LAST_FRONTEND_BUNDLE_VERSION"

        backend_exit=2
        frontend_exit=2
        backend_pull_state="failed-precheck"
        frontend_pull_state="failed-precheck"
        backend_result="failed"
        frontend_result="failed"
        alert_code="AUTO_UPDATE_FAILED"
        severity="critical"
        summary="Sender auto-update failed during prechecks."

        post_auto_update_alert \
            "$alert_code" \
            "$severity" \
            "$summary" \
            "$backend_exit" \
            "$frontend_exit" \
            "$backend_pull_state" \
            "$frontend_pull_state" \
            "$SCRIPT_BACKEND_UPDATE_STATE" \
            "$SCRIPT_FRONTEND_UPDATE_STATE" \
            "$target_backend_ref" \
            "$target_frontend_ref" \
            "$target_backend_digest" \
            "$target_frontend_digest" \
            "$SENDER_BUNDLE_TAG" \
            "$target_backend_version" \
            "$target_frontend_version" \
            "$LAST_SCRIPT_SYNC_RESULT"

        evaluate_and_post_disk_space_alert || true

        write_update_state_files \
            "$backend_result" \
            "$frontend_result" \
            "$backend_exit" \
            "$frontend_exit" \
            "$backend_pull_state" \
            "$frontend_pull_state" \
            "$target_backend_ref" \
            "$target_frontend_ref" \
            "$target_backend_digest" \
            "$target_frontend_digest" \
            "$SENDER_BUNDLE_TAG" \
            "$target_backend_version" \
            "$target_frontend_version" \
            "$LAST_SCRIPT_SYNC_RESULT" \
            "$LAST_ALERT_POST_RESULT"
        return 1
    fi

    target_backend_ref="$LAST_BACKEND_IMAGE_REF"
    target_frontend_ref="$LAST_FRONTEND_IMAGE_REF"
    target_backend_digest="$LAST_BACKEND_DIGEST"
    target_frontend_digest="$LAST_FRONTEND_DIGEST"
    target_backend_version="$LAST_BUNDLE_VERSION"
    target_frontend_version="$LAST_FRONTEND_BUNDLE_VERSION"

    backend_previous_ref="$(get_container_repo_digest "$CONTAINER" "$SENDER_BACKEND_IMAGE_REPO")"
    frontend_previous_ref="$(get_container_repo_digest "sender-frontend" "$SENDER_FRONTEND_IMAGE_REPO")"
    backend_current_digest="$backend_previous_ref"
    frontend_current_digest="$frontend_previous_ref"

    if [[ -n "$backend_current_digest" && -n "$target_backend_digest" && "$backend_current_digest" == "${SENDER_BACKEND_IMAGE_REPO}@${target_backend_digest}" ]] && ! backend_container_config_drifted; then
        backend_exit=0
        backend_pull_state="no-change"
        backend_result="no-change"
    else
        LAST_PULL_RESULT="unknown"
        backend_output="$(update_container "$target_backend_ref" 2>&1)"
        backend_exit=$?
        if [[ -n "$backend_output" ]]; then
            echo "$backend_output"
        fi
        if [[ $backend_exit -eq 0 ]]; then
            backend_pull_state="updated"
            backend_result="updated"
        else
            backend_pull_state="failed"
            backend_result="failed"
        fi
    fi

    if [[ -n "$frontend_current_digest" && -n "$target_frontend_digest" && "$frontend_current_digest" == "${SENDER_FRONTEND_IMAGE_REPO}@${target_frontend_digest}" ]]; then
        frontend_exit=0
        frontend_pull_state="no-change"
        frontend_result="no-change"
    elif [[ -x /usr/local/bin/sender-frontend ]]; then
        frontend_output="$(/usr/local/bin/sender-frontend UPDATE "$target_frontend_ref" 2>&1)"
        frontend_exit=$?
        if [[ -n "$frontend_output" ]]; then
            echo "$frontend_output"
        fi
        if [[ $frontend_exit -eq 0 ]]; then
            frontend_pull_state="updated"
            frontend_result="updated"
        else
            frontend_pull_state="failed"
            frontend_result="failed"
        fi
    else
        frontend_exit=127
        frontend_pull_state="missing-script"
        frontend_result="failed"
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "sender-frontend script is missing or not executable."
    fi

    if [[ $backend_exit -ne 0 || $frontend_exit -ne 0 ]]; then
        attempt_auto_update_rollback \
            "$backend_previous_ref" \
            "$frontend_previous_ref" \
            "${SENDER_BACKEND_IMAGE_REPO}@${target_backend_digest}" \
            "${SENDER_FRONTEND_IMAGE_REPO}@${target_frontend_digest}" || true
    fi

    finalize_auto_update_migration_state "$backend_was_stale" "$tunnel_was_stale"

    if [[ $backend_exit -ne 0 || $frontend_exit -ne 0 ]]; then
        alert_code="AUTO_UPDATE_FAILED"
        severity="critical"
        summary="Sender auto-update executed with failures."
    elif [[ "$backend_pull_state" == "no-change" && "$frontend_pull_state" == "no-change" ]]; then
        alert_code="AUTO_UPDATE_NO_CHANGE"
        severity="info"
        if [[ "$LAST_MIGRATION_RESULT" == "completed" || "$LAST_MIGRATION_RESULT" == "partial" || "$LAST_MIGRATION_RESULT" == "failed" ]]; then
            summary="$LAST_MIGRATION_SUMMARY"
        else
            summary="Sender auto-update executed; no newer images were available."
        fi
    else
        alert_code="AUTO_UPDATE_EXECUTED"
        severity="info"
        if [[ "$LAST_MIGRATION_RESULT" == "completed" || "$LAST_MIGRATION_RESULT" == "partial" || "$LAST_MIGRATION_RESULT" == "failed" ]]; then
            summary="$LAST_MIGRATION_SUMMARY"
        else
            summary="Sender auto-update executed successfully."
        fi
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
        "$SCRIPT_FRONTEND_UPDATE_STATE" \
        "$target_backend_ref" \
        "$target_frontend_ref" \
        "$target_backend_digest" \
        "$target_frontend_digest" \
        "$SENDER_BUNDLE_TAG" \
        "$target_backend_version" \
        "$target_frontend_version" \
        "$LAST_SCRIPT_SYNC_RESULT"

    evaluate_and_post_disk_space_alert || true

    write_update_state_files \
        "$backend_result" \
        "$frontend_result" \
        "$backend_exit" \
        "$frontend_exit" \
        "$backend_pull_state" \
        "$frontend_pull_state" \
        "$target_backend_ref" \
        "$target_frontend_ref" \
        "$target_backend_digest" \
        "$target_frontend_digest" \
        "$SENDER_BUNDLE_TAG" \
        "$target_backend_version" \
        "$target_frontend_version" \
        "$LAST_SCRIPT_SYNC_RESULT" \
        "$LAST_ALERT_POST_RESULT"

    if [[ $backend_exit -ne 0 || $frontend_exit -ne 0 ]]; then
        return 1
    fi

    cleanup_dangling_images_compatible || true
    return 0
}

function update_container_with_state() {
    local backend_output backend_exit backend_pull_state backend_result
    local target_ref="$1"
    local target_digest_ref
    local target_bundle_version
    local current_digest

    refresh_sender_scripts
    ensure_host_scripts_dir || true
    LAST_ROLLBACK_RESULT="not-applicable"
    LAST_ROLLBACK_BACKEND_EXIT=0
    LAST_ROLLBACK_FRONTEND_EXIT=0
    LAST_ROLLBACK_BACKEND_TARGET="none"
    LAST_ROLLBACK_FRONTEND_TARGET="none"

    if [[ -z "$target_ref" ]]; then
        target_ref="${SENDER_BACKEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}"
    fi
    target_digest_ref="$(resolve_image_ref "$target_ref")" || return 1
    LAST_BACKEND_IMAGE_REF="$target_ref"
    LAST_BACKEND_DIGEST="${target_digest_ref##*@}"
    target_bundle_version="$(get_image_label "$target_digest_ref" "org.upri.sender.bundle.version")"
    LAST_BUNDLE_VERSION="${target_bundle_version:-unknown}"
    LAST_FRONTEND_BUNDLE_VERSION="$LAST_BUNDLE_VERSION"
    LAST_FRONTEND_IMAGE_REF="${SENDER_FRONTEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}"

    current_digest="$(get_container_repo_digest "$CONTAINER" "$SENDER_BACKEND_IMAGE_REPO")"
    if [[ -n "$current_digest" && "$current_digest" == "$target_digest_ref" ]] && ! backend_container_config_drifted; then
        backend_exit=0
        backend_pull_state="no-change"
        backend_result="no-change"
    else
        LAST_PULL_RESULT="unknown"
        backend_output="$(update_container "$target_ref" 2>&1)"
        backend_exit=$?
        if [[ -n "$backend_output" ]]; then
            echo "$backend_output"
        fi

        if [[ $backend_exit -eq 0 ]]; then
            backend_pull_state="updated"
            backend_result="updated"
        else
            backend_pull_state="failed"
            backend_result="failed"
        fi
    fi

    write_update_state_files \
        "$backend_result" \
        "not-run" \
        "$backend_exit" \
        "0" \
        "$backend_pull_state" \
        "not-run" \
        "$LAST_BACKEND_IMAGE_REF" \
        "$LAST_FRONTEND_IMAGE_REF" \
        "$LAST_BACKEND_DIGEST" \
        "unknown" \
        "$SENDER_BUNDLE_TAG" \
        "$LAST_BUNDLE_VERSION" \
        "unknown" \
        "$LAST_SCRIPT_SYNC_RESULT" \
        "$LAST_ALERT_POST_RESULT"

    if [[ $backend_exit -eq 0 ]]; then
        cleanup_dangling_images_compatible || true
    fi

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
        install_update_timer || return $?
        install_remote_tunnel_service || return $?
        return 0
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
          install_update_timer || return $?
          install_remote_tunnel_service || return $?
          return 0
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
OnCalendar=daily
RandomizedDelaySec=45m
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
        install_watchdog_timer
        return $?
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to enable or start $UPDATE_TIMER."
        return 1
    fi
}

function install_watchdog_timer() {
    local interval_minutes

    interval_minutes="$(normalize_positive_int "$WATCHDOG_INTERVAL_MINUTES" "$WATCHDOG_INTERVAL_MINUTES_DEFAULT" 1)"

    cat <<EOF > "$WATCHDOG_SERVICE_FILE"
[Unit]
Description=UPRI: Sender Stack Watchdog Service
ConditionPathExists=/usr/local/bin/sender-backend
ConditionPathExists=/usr/local/bin/sender-frontend
Wants=docker.service network-online.target
After=docker.service network-online.target

[Service]
Type=oneshot
User=myshake
ExecStart=/usr/local/bin/sender-backend WATCHDOG_CHECK

[Install]
WantedBy=multi-user.target
EOF
    if [[ $? -ne 0 ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to write $WATCHDOG_SERVICE_FILE."
        return 1
    fi

    cat <<EOF > "$WATCHDOG_TIMER_FILE"
[Unit]
Description=UPRI: Sender Stack Watchdog Timer

[Timer]
OnBootSec=10m
OnUnitActiveSec=${interval_minutes}m
RandomizedDelaySec=45s
Unit=$WATCHDOG_SERVICE
Persistent=true

[Install]
WantedBy=timers.target
EOF
    if [[ $? -ne 0 ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to write $WATCHDOG_TIMER_FILE."
        return 1
    fi

    systemctl daemon-reload
    if systemctl enable --now "$WATCHDOG_TIMER" >/dev/null 2>&1; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "$WATCHDOG_TIMER enabled and started."
        return 0
    fi

    echo -en "[\e[1;31mFAILED\e[0m] "
    echo "Failed to enable or start $WATCHDOG_TIMER."
    return 1
}

function write_remote_tunnel_env_template_if_missing() {
    local env_file="${REMOTE_TUNNEL_ENV_FILE:-$REMOTE_TUNNEL_ENV_FILE_DEFAULT}"
    local env_dir
    local tmp_file

    REMOTE_TUNNEL_ENV_FILE="$env_file"
    if [[ -f "$env_file" ]]; then
        return 0
    fi

    env_dir="$(dirname "$env_file")"
    if ! mkdir -p "$env_dir" >/dev/null 2>&1; then
        if ! (command -v sudo >/dev/null 2>&1 && sudo -n mkdir -p "$env_dir" >/dev/null 2>&1); then
            echo -en "[\e[1;33mWARN\e[0m] "
            echo "Unable to create remote tunnel env directory: $env_dir"
            return 1
        fi
    fi

    tmp_file="$(mktemp "/tmp/upri-sender-remote-tunnel-env.XXXXXX")" || return 1
    cat <<EOF > "$tmp_file"
# Sender reverse tunnel configuration (wstunnel)
REMOTE_TUNNEL_ENABLED=false
REMOTE_TUNNEL_DEVICE_ID=
REMOTE_TUNNEL_REMOTE_PORT=
REMOTE_TUNNEL_LOCAL_HOST=127.0.0.1
REMOTE_TUNNEL_LOCAL_PORT=22
REMOTE_TUNNEL_KEY_PATH=/etc/upri/remote-tunnel/id_ed25519
REMOTE_TUNNEL_STATE_FILE=/var/lib/upri-sender/remote-tunnel-state.json
REMOTE_TUNNEL_PID_FILE=/tmp/upri-sender-remote-tunnel.pid
REMOTE_TUNNEL_AUTO_REGISTER_ENABLED=false
REMOTE_TUNNEL_ENROLL_ENDPOINT=
REMOTE_TUNNEL_ENROLL_TOKEN=
REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC=15
REMOTE_TUNNEL_WSS_URL=
REMOTE_TUNNEL_WSS_PATH_PREFIX=
REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY=
REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY=
EOF

    if install_data_payload "$tmp_file" "$env_file" 0640; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Created remote tunnel env template at $env_file."
        rm -f "$tmp_file" >/dev/null 2>&1
        return 0
    fi

    rm -f "$tmp_file" >/dev/null 2>&1
    echo -en "[\e[1;33mWARN\e[0m] "
    echo "Unable to write remote tunnel env template at $env_file."
    return 1
}

function install_remote_tunnel_service() {
    cat <<EOF > "$REMOTE_TUNNEL_SERVICE_FILE"
[Unit]
Description=UPRI: Sender Reverse WebSocket Tunnel Service
ConditionPathExists=/usr/local/bin/sender-backend
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=myshake
EnvironmentFile=-$REMOTE_TUNNEL_ENV_FILE_DEFAULT
ExecStart=/usr/local/bin/sender-backend REMOTE_TUNNEL_START
Restart=always
RestartSec=10
RestartPreventExitStatus=3
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
    if [[ $? -ne 0 ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to write $REMOTE_TUNNEL_SERVICE_FILE."
        return 1
    fi

    write_remote_tunnel_env_template_if_missing || true

    systemctl daemon-reload
    if ! systemctl enable "$REMOTE_TUNNEL_SERVICE" >/dev/null 2>&1; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to enable $REMOTE_TUNNEL_SERVICE."
        return 1
    fi

    echo -en "[  \e[32mOK\e[0m  ] "
    echo "$REMOTE_TUNNEL_SERVICE installed and enabled."

    load_remote_tunnel_env
    remote_tunnel_apply_runtime_permissions || true
    remote_tunnel_provision_operator_key || true
    remote_tunnel_provision_operator_shell_key || true
    remote_tunnel_attempt_auto_register || true
    remote_tunnel_apply_runtime_permissions || true
    remote_tunnel_provision_operator_key || true
    remote_tunnel_provision_operator_shell_key || true
    load_remote_tunnel_env
    remote_tunnel_validate_config
    case $? in
        0)
            if systemctl restart "$REMOTE_TUNNEL_SERVICE" >/dev/null 2>&1; then
                echo -en "[  \e[32mOK\e[0m  ] "
                echo "$REMOTE_TUNNEL_SERVICE started."
            else
                echo -en "[\e[1;33mWARN\e[0m] "
                echo "$REMOTE_TUNNEL_SERVICE is enabled but did not start cleanly."
            fi
            ;;
        3)
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Remote tunnel is disabled in $REMOTE_TUNNEL_ENV_FILE; service start skipped."
            ;;
        *)
            echo -en "[\e[1;33mWARN\e[0m] "
            echo "Remote tunnel service installed but config is incomplete. Fill $REMOTE_TUNNEL_ENV_FILE before starting."
            ;;
    esac
    return 0
}

function uninstall_remote_tunnel_service() {
    local removed=0
    local failed=0
    local state_path

    sudo systemctl stop "$REMOTE_TUNNEL_SERVICE" >/dev/null 2>&1
    sudo systemctl disable "$REMOTE_TUNNEL_SERVICE" >/dev/null 2>&1

    if [[ -f "$REMOTE_TUNNEL_SERVICE_FILE" ]]; then
        if sudo rm -f "$REMOTE_TUNNEL_SERVICE_FILE"; then
            removed=1
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove $REMOTE_TUNNEL_SERVICE_FILE."
            failed=1
        fi
    fi

    rm -f "$REMOTE_TUNNEL_PID_FILE" >/dev/null 2>&1 || true
    state_path="$(resolve_remote_tunnel_state_file_path)"
    sudo rm -f "$state_path" >/dev/null 2>&1 || true
    if [[ "$state_path" != "/tmp/upri-sender/remote-tunnel-state.json" ]]; then
        sudo rm -f "/tmp/upri-sender/remote-tunnel-state.json" >/dev/null 2>&1 || true
    fi

    if ! sudo systemctl daemon-reload >/dev/null 2>&1; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to reload systemd daemon."
        failed=1
    fi

    if [[ $failed -eq 1 ]]; then
        return 1
    fi

    if [[ $removed -eq 1 ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Remote tunnel service removed."
    fi
    return 0
}

function uninstall_update_timer() {
    local removed=0
    local failed=0

    sudo systemctl stop "$UPDATE_TIMER" >/dev/null 2>&1
    sudo systemctl disable "$UPDATE_TIMER" >/dev/null 2>&1
    if ! uninstall_watchdog_timer; then
        failed=1
    fi

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

function uninstall_watchdog_timer() {
    local removed=0
    local failed=0
    local state_path

    sudo systemctl stop "$WATCHDOG_TIMER" >/dev/null 2>&1
    sudo systemctl disable "$WATCHDOG_TIMER" >/dev/null 2>&1

    if [[ -f "$WATCHDOG_TIMER_FILE" ]]; then
        if sudo rm -f "$WATCHDOG_TIMER_FILE"; then
            removed=1
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove $WATCHDOG_TIMER_FILE."
            failed=1
        fi
    fi

    if [[ -f "$WATCHDOG_SERVICE_FILE" ]]; then
        if sudo rm -f "$WATCHDOG_SERVICE_FILE"; then
            removed=1
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove $WATCHDOG_SERVICE_FILE."
            failed=1
        fi
    fi

    state_path="$(resolve_watchdog_state_file_path)"
    if [[ -f "$state_path" ]]; then
        sudo rm -f "$state_path" >/dev/null 2>&1 || true
    fi
    if [[ "$state_path" != "/tmp/upri-sender/watchdog-state.env" && -f "/tmp/upri-sender/watchdog-state.env" ]]; then
        sudo rm -f "/tmp/upri-sender/watchdog-state.env" >/dev/null 2>&1 || true
    fi

    if [[ $failed -eq 1 ]]; then
        return 1
    fi

    if [[ $removed -eq 1 ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Watchdog timer removed."
    fi
    return 0
}

function pull_container() {
    local requested_ref="${1:-${SENDER_BACKEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}}"
    local resolved_ref

    LAST_PULL_RESULT="unknown"
    resolved_ref="$(resolve_image_ref "$requested_ref")" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to pull image $requested_ref."
        return 1
    }

    LAST_BACKEND_IMAGE_REF="$requested_ref"
    LAST_BACKEND_DIGEST="${resolved_ref##*@}"
    LAST_BUNDLE_VERSION="$(get_image_label "$resolved_ref" "org.upri.sender.bundle.version")"
    if [[ -z "$LAST_BUNDLE_VERSION" ]]; then
        LAST_BUNDLE_VERSION="unknown"
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
    local requested_ref="${2:-${SENDER_BACKEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}}"
    local target_image_ref="$requested_ref"
    local target_digest_ref=""
    local docker_network_flag
    local -a alert_env_flags=()

    target_digest_ref="$(get_repo_digest_for_image_ref "$target_image_ref")"
    LAST_BACKEND_IMAGE_REF="$target_image_ref"
    if [[ -n "$target_digest_ref" ]]; then
        LAST_BACKEND_DIGEST="${target_digest_ref##*@}"
    elif is_digest_ref "$target_image_ref"; then
        LAST_BACKEND_DIGEST="${target_image_ref##*@}"
    else
        LAST_BACKEND_DIGEST="unknown"
    fi
    ensure_host_scripts_dir || true
    write_alert_runtime_env_template_if_missing || true

    if [[ -n "${RSHAKE_ALERTS_ENABLED:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERTS_ENABLED=${RSHAKE_ALERTS_ENABLED}")
    fi
    if [[ -n "${W1_RS_ALERT_PATH:-}" ]]; then
        alert_env_flags+=(--env "W1_RS_ALERT_PATH=${W1_RS_ALERT_PATH}")
    fi
    if [[ -n "${RSHAKE_ALERT_POST_TIMEOUT_MS:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_POST_TIMEOUT_MS=${RSHAKE_ALERT_POST_TIMEOUT_MS}")
    fi
    if [[ -n "${RSHAKE_ALERT_SHARED_SECRET:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_SHARED_SECRET=${RSHAKE_ALERT_SHARED_SECRET}")
    fi
    if [[ -n "${RSHAKE_ALERT_RETRY_ATTEMPTS:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_RETRY_ATTEMPTS=${RSHAKE_ALERT_RETRY_ATTEMPTS}")
    fi
    if [[ -n "${RSHAKE_ALERT_RETRY_BASE_MS:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_RETRY_BASE_MS=${RSHAKE_ALERT_RETRY_BASE_MS}")
    fi
    if [[ -n "${RSHAKE_ALERT_MIN_INTERVAL_SEC:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_MIN_INTERVAL_SEC=${RSHAKE_ALERT_MIN_INTERVAL_SEC}")
    fi
    if [[ -n "${RSHAKE_ALERT_QUEUE_ENABLED:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_QUEUE_ENABLED=${RSHAKE_ALERT_QUEUE_ENABLED}")
    fi
    if [[ -n "${RSHAKE_ALERT_QUEUE_FILE:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_QUEUE_FILE=${RSHAKE_ALERT_QUEUE_FILE}")
    fi
    if [[ -n "${RSHAKE_ALERT_QUEUE_MAX_SIZE:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_QUEUE_MAX_SIZE=${RSHAKE_ALERT_QUEUE_MAX_SIZE}")
    fi
    if [[ -n "${RSHAKE_ALERT_QUEUE_MAX_ATTEMPTS:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_QUEUE_MAX_ATTEMPTS=${RSHAKE_ALERT_QUEUE_MAX_ATTEMPTS}")
    fi
    if [[ -n "${RSHAKE_ALERT_QUEUE_BACKOFF_MS:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_QUEUE_BACKOFF_MS=${RSHAKE_ALERT_QUEUE_BACKOFF_MS}")
    fi
    if [[ -n "${RSHAKE_ALERT_COOLDOWN_STATE_FILE:-}" ]]; then
        alert_env_flags+=(--env "RSHAKE_ALERT_COOLDOWN_STATE_FILE=${RSHAKE_ALERT_COOLDOWN_STATE_FILE}")
    fi
    if [[ -n "${W1_ALLOW_INSECURE_TLS:-}" ]]; then
        alert_env_flags+=(--env "W1_ALLOW_INSECURE_TLS=${W1_ALLOW_INSECURE_TLS}")
    fi
    if [[ -n "${SENDER_STRUCTURED_LOGS:-}" ]]; then
        alert_env_flags+=(--env "SENDER_STRUCTURED_LOGS=${SENDER_STRUCTURED_LOGS}")
    fi
    if [[ -n "${METRICS_PERSIST_HEALTH_HISTORY:-}" ]]; then
        alert_env_flags+=(--env "METRICS_PERSIST_HEALTH_HISTORY=${METRICS_PERSIST_HEALTH_HISTORY}")
    fi
    if [[ -n "${METRICS_HEALTH_HISTORY_FILE:-}" ]]; then
        alert_env_flags+=(--env "METRICS_HEALTH_HISTORY_FILE=${METRICS_HEALTH_HISTORY_FILE}")
    fi
    if [[ -n "${METRICS_HEALTH_HISTORY_LIMIT:-}" ]]; then
        alert_env_flags+=(--env "METRICS_HEALTH_HISTORY_LIMIT=${METRICS_HEALTH_HISTORY_LIMIT}")
    fi
    if [[ -n "${METRICS_HEALTH_HISTORY_FLUSH_MS:-}" ]]; then
        alert_env_flags+=(--env "METRICS_HEALTH_HISTORY_FLUSH_MS=${METRICS_HEALTH_HISTORY_FLUSH_MS}")
    fi
    if [[ -n "${AUTO_UPDATE_ALERT_ENDPOINT:-}" ]]; then
        alert_env_flags+=(--env "AUTO_UPDATE_ALERT_ENDPOINT=${AUTO_UPDATE_ALERT_ENDPOINT}")
    fi
    if [[ -n "${AUTO_UPDATE_ALERT_TIMEOUT_SEC:-}" ]]; then
        alert_env_flags+=(--env "AUTO_UPDATE_ALERT_TIMEOUT_SEC=${AUTO_UPDATE_ALERT_TIMEOUT_SEC}")
    fi
    alert_env_flags+=(--env "SENDER_SCRIPT_SYNC_MODE=${SENDER_SCRIPT_SYNC_MODE}")
    alert_env_flags+=(--env "SENDER_SCRIPT_SYNC_TIMEOUT_SEC=${SENDER_SCRIPT_SYNC_TIMEOUT_SEC}")
    alert_env_flags+=(--env "SENDER_HOST_SCRIPTS_DIR=${CONTAINER_HOST_SCRIPTS_DIR}")
    alert_env_flags+=(--env "RSHAKE_ALERT_RUNTIME_ENV_FILE=${CONTAINER_ALERT_RUNTIME_ENV_FILE}")
    alert_env_flags+=(--env "SENDER_BUNDLE_TAG=${SENDER_BUNDLE_TAG}")
    if [[ -n "$LAST_BUNDLE_VERSION" && "$LAST_BUNDLE_VERSION" != "unknown" ]]; then
        alert_env_flags+=(--env "SENDER_IMAGE_BUNDLE_VERSION=${LAST_BUNDLE_VERSION}")
    fi

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
            --restart unless-stopped \
            --add-host "$in_docker_hostname:$host_ip" \
            --volume /sys/fs/cgroup:/sys/fs/cgroup:ro \
            --volume /opt/settings:/opt/settings:ro \
            --volume "$VOLUME":/app/localDBs \
            --volume "${SENDER_HOST_SCRIPTS_DIR}:${CONTAINER_HOST_SCRIPTS_DIR}" \
            --volume "${ALERT_RUNTIME_DIR}:${CONTAINER_ALERT_RUNTIME_DIR}" \
            --env LOCALDBS_DIRECTORY=/app/localDBs \
            --env "W1_PROD_IP=${W1_PROD_IP_DEFAULT}" \
            "${alert_env_flags[@]}" \
            --log-driver json-file \
            --log-opt max-size=10m \
            --log-opt max-file=3 \
            --label "$DNS_MODE_LABEL_KEY=$dns_mode" \
            "${DNS_FLAGS[@]}" \
            "$docker_network_flag" "$DOCKER_NETWORK" \
            "$target_image_ref"
            # 1st volume: workaround for docker's oci runtime error
            # 2nd volume: contains NET and STAT info
            # 3rd volume: will contain local file storage of sender-backend server
            # 4th volume: host scripts directory for startup hook script sync
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
    local target_image_ref="$1"

    if [[ $(docker inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null) == "true" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER is already running."
        ensure_container_restart_policy "$CONTAINER" >/dev/null 2>&1 || true
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
        ensure_container_restart_policy "$CONTAINER" >/dev/null 2>&1 || true

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

        if ! create_container "host-policy" "$target_image_ref"; then
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
    local target_image_ref="$1"

    stop_container
    remove_container
    pull_container "$target_image_ref" || return 1
    create_network
    create_container "auto" "$LAST_BACKEND_IMAGE_REF"
    start_container "$LAST_BACKEND_IMAGE_REF"
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
    local target_ref="${1:-${SENDER_BACKEND_IMAGE_REPO}:${SENDER_BUNDLE_TAG}}"

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
        uninstall_remote_tunnel_service || true
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
        uninstall_remote_tunnel_service || true
        uninstall_update_timer
        return $?
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to remove unit file $UNIT_FILE."
        return 1
    fi
}

## execute function based on argument
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
        create_container "$2" "$3"
        ;;
    "START")
        start_container "$2"
        ;;
    "UPDATE")
        update_container_with_state "$2"
        ;;
    "UPDATE_STACK")
        run_update_stack_with_lock
        ;;
    "WATCHDOG_CHECK")
        run_watchdog_check_with_lock
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
    "INSTALL_WATCHDOG_TIMER")
        install_watchdog_timer
        ;;
    "UNINSTALL_WATCHDOG_TIMER")
        uninstall_watchdog_timer
        ;;
    "INSTALL_REMOTE_TUNNEL_SERVICE")
        install_remote_tunnel_service
        ;;
    "UNINSTALL_REMOTE_TUNNEL_SERVICE")
        uninstall_remote_tunnel_service
        ;;
    "REMOTE_TUNNEL_START")
        remote_tunnel_start
        ;;
    "REMOTE_TUNNEL_STOP")
        remote_tunnel_stop
        ;;
    "REMOTE_TUNNEL_STATUS")
        remote_tunnel_status
        ;;
    "REMOTE_ACTION_EXECUTE")
        remote_action_execute "$2" "$3"
        ;;
    "REMOTE_ACTION_DISPATCH")
        remote_action_dispatch
        ;;
    *)
        echo "Invalid argument. Usage: ./script.sh [INSTALL_SERVICE|INSTALL_UPDATE_TIMER|INSTALL_WATCHDOG_TIMER|INSTALL_REMOTE_TUNNEL_SERVICE|NETWORK_SETUP|PULL [image-ref]|CREATE [dns-mode] [image-ref]|START [image-ref]|STOP|UPDATE [image-ref]|UPDATE_STACK|WATCHDOG_CHECK|REMOTE_TUNNEL_START|REMOTE_TUNNEL_STOP|REMOTE_TUNNEL_STATUS|REMOTE_ACTION_EXECUTE <UNLINK|RELINK|ADD_SERVER|REMOVE_SERVER|LIST_SERVERS> [payload-b64]|REMOTE_ACTION_DISPATCH|REMOVE_NETWORK|REMOVE_VOLUME|REMOVE_IMAGE [image-ref]|REMOVE_CONTAINER|UNINSTALL_SERVICE|UNINSTALL_UPDATE_TIMER|UNINSTALL_WATCHDOG_TIMER|UNINSTALL_REMOTE_TUNNEL_SERVICE]"
        ;;
esac
