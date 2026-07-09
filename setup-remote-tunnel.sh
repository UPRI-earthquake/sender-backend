#!/bin/bash
set -euo pipefail

ENV_FILE_DEFAULT="/etc/upri/sender-remote-tunnel.env"
SERVICE_NAME="sender-remote-tunnel.service"
SENDER_BACKEND_CMD_DEFAULT="sender-backend"
AUTO_REGISTER_DEFAULT="true"
LOCAL_HOST_DEFAULT="127.0.0.1"
LOCAL_PORT_DEFAULT="22"
ENROLL_TIMEOUT_DEFAULT="15"
WSS_URL_DEFAULT=""
WSS_PATH_PREFIX_DEFAULT=""
WSTUNNEL_VERSION_DEFAULT="10.5.2"

ENV_FILE="$ENV_FILE_DEFAULT"
SENDER_BACKEND_CMD="${SENDER_BACKEND_CMD:-$SENDER_BACKEND_CMD_DEFAULT}"
AUTO_REGISTER="$AUTO_REGISTER_DEFAULT"
ENROLL_TOKEN="${REMOTE_TUNNEL_ENROLL_TOKEN:-}"
ENROLL_ENDPOINT="${REMOTE_TUNNEL_ENROLL_ENDPOINT:-}"
DEVICE_ID="${REMOTE_TUNNEL_DEVICE_ID:-}"
LOCAL_HOST="$LOCAL_HOST_DEFAULT"
LOCAL_PORT="$LOCAL_PORT_DEFAULT"
ENROLL_TIMEOUT="$ENROLL_TIMEOUT_DEFAULT"
WSS_URL="${REMOTE_TUNNEL_WSS_URL:-$WSS_URL_DEFAULT}"
WSS_PATH_PREFIX="${REMOTE_TUNNEL_WSS_PATH_PREFIX:-$WSS_PATH_PREFIX_DEFAULT}"
OPERATOR_PUBLIC_KEY="${REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY:-}"
OPERATOR_SSH_PUBLIC_KEY="${REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY:-}"
WSTUNNEL_VERSION="${REMOTE_TUNNEL_WSTUNNEL_VERSION:-$WSTUNNEL_VERSION_DEFAULT}"
SKIP_RESTART="false"

usage() {
    cat <<'EOF'
Usage:
  sudo ./setup-remote-tunnel.sh --enroll-token <token> [options]

Options:
  --enroll-token <token>            Enrollment bearer token (optional if auto-discovery succeeds)
  --enroll-endpoint <url>           Enrollment endpoint override (optional)
  --device-id <id>                  Device ID override (optional; auto-derived when omitted)
  --local-host <host>               Local SSH source host (default: 127.0.0.1)
  --local-port <port>               Local SSH source port (default: 22)
  --enroll-timeout-sec <seconds>    Enrollment request timeout (default: 15)
  --wss-url <url>                   WebSocket tunnel endpoint override (optional)
  --wss-path-prefix <prefix>        WS upgrade path prefix override (optional)
  --operator-public-key <key>       Optional SSH public key for forced-command remote actions
  --operator-ssh-public-key <key>   Optional SSH public key for interactive operator shell access
  --wstunnel-version <version>      Pinned wstunnel release version for auto-install (default: $WSTUNNEL_VERSION_DEFAULT)
  --auto-register <true|false>      Enable/disable auto-registration (default: true)
  --env-file <path>                 Env file path (default: /etc/upri/sender-remote-tunnel.env)
  --sender-backend-cmd <cmd>        sender-backend command path (default: sender-backend)
  --skip-restart                    Do not restart service at the end
  -h, --help                        Show this help

Examples:
  sudo ./setup-remote-tunnel.sh --enroll-token "$TOKEN"
  sudo ./setup-remote-tunnel.sh --enroll-token "$TOKEN" --enroll-endpoint "https://earthquake.up.edu.ph/api/device/tunnel/enroll"

Host package prerequisites:
  sudo apt-get update
  sudo apt-get install -y openssh-client
  # wstunnel is auto-installed from GitHub release when missing
EOF
}

is_truthy() {
    local value="${1:-}"
    value="$(echo "$value" | tr '[:upper:]' '[:lower:]')"
    case "$value" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_bool() {
    local value="${1:-}"
    if is_truthy "$value"; then
        printf "true"
        return 0
    fi
    value="$(echo "$value" | tr '[:upper:]' '[:lower:]')"
    case "$value" in
        0|false|no|off)
            printf "false"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_valid_port() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    (( value >= 1 && value <= 65535 )) || return 1
    return 0
}

is_valid_positive_int() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    (( value >= 1 )) || return 1
    return 0
}

env_escape() {
    local value="$1"
    value="${value//$'\r'/}"
    value="${value//$'\n'/}"
    value="${value//\'/\'\\\'\'}"
    printf "'%s'" "$value"
}

emit_env_line() {
    local key="$1"
    local value="${2-}"
    printf "%s=%s\n" "$key" "$(env_escape "$value")"
}

extract_access_token_from_json_file() {
    local file_path="$1"
    local token
    [[ -r "$file_path" ]] || return 1

    token="$(tr -d '\r\n' < "$file_path" | sed -n 's/.*"accessToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [[ -n "$token" ]] || return 1
    printf "%s" "$token"
    return 0
}

resolve_token_from_env_file() {
    local token
    [[ -r "$ENV_FILE" ]] || return 1

    token="$(bash -c 'set +u; source "$1" >/dev/null 2>&1 || true; printf "%s" "${REMOTE_TUNNEL_ENROLL_TOKEN:-}"' _ "$ENV_FILE" 2>/dev/null || true)"
    [[ -n "$token" ]] || return 1
    printf "%s" "$token"
    return 0
}

resolve_operator_key_from_env_file_if_missing() {
    local existing_key
    [[ -r "$ENV_FILE" ]] || return 0

    if [[ -z "${OPERATOR_PUBLIC_KEY:-}" ]]; then
        existing_key="$(bash -c 'set +u; source "$1" >/dev/null 2>&1 || true; printf "%s" "${REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY:-}"' _ "$ENV_FILE" 2>/dev/null || true)"
        if [[ -n "$existing_key" ]]; then
            OPERATOR_PUBLIC_KEY="$existing_key"
        fi
    fi

    if [[ -z "${OPERATOR_SSH_PUBLIC_KEY:-}" ]]; then
        existing_key="$(bash -c 'set +u; source "$1" >/dev/null 2>&1 || true; printf "%s" "${REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY:-}"' _ "$ENV_FILE" 2>/dev/null || true)"
        if [[ -n "$existing_key" ]]; then
            OPERATOR_SSH_PUBLIC_KEY="$existing_key"
        fi
    fi
    return 0
}

resolve_token_from_running_container() {
    local token
    command -v docker >/dev/null 2>&1 || return 1

    token="$(docker exec sender-backend node -e 'const fs=require("fs");try{const j=JSON.parse(fs.readFileSync("/app/localDBs/token.json","utf8"));if(typeof j.accessToken==="string"){process.stdout.write(j.accessToken)}}catch(_){process.exit(0)}' 2>/dev/null || true)"
    [[ -n "$token" ]] || return 1
    printf "%s" "$token"
    return 0
}

resolve_token_from_container_mount() {
    local mount_path
    local token_file
    command -v docker >/dev/null 2>&1 || return 1

    mount_path="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/localDBs"}}{{.Source}}{{end}}{{end}}' sender-backend 2>/dev/null || true)"
    [[ -n "$mount_path" ]] || return 1

    token_file="${mount_path%/}/token.json"
    extract_access_token_from_json_file "$token_file"
}

resolve_token_from_default_paths() {
    local token_file
    for token_file in \
        "/var/lib/docker/volumes/UPRI-volume/_data/token.json" \
        "/app/localDBs/token.json"
    do
        if extract_access_token_from_json_file "$token_file" >/dev/null 2>&1; then
            extract_access_token_from_json_file "$token_file"
            return 0
        fi
    done
    return 1
}

resolve_enroll_token_if_missing() {
    local resolved=""
    if [[ -n "$ENROLL_TOKEN" ]]; then
        return 0
    fi

    resolved="$(resolve_token_from_env_file || true)"
    if [[ -n "$resolved" ]]; then
        ENROLL_TOKEN="$resolved"
        echo "Using existing enrollment token from $ENV_FILE."
        return 0
    fi

    resolved="$(resolve_token_from_running_container || true)"
    if [[ -n "$resolved" ]]; then
        ENROLL_TOKEN="$resolved"
        echo "Using access token from running sender-backend container."
        return 0
    fi

    resolved="$(resolve_token_from_container_mount || true)"
    if [[ -n "$resolved" ]]; then
        ENROLL_TOKEN="$resolved"
        echo "Using access token from sender-backend localDBs volume."
        return 0
    fi

    resolved="$(resolve_token_from_default_paths || true)"
    if [[ -n "$resolved" ]]; then
        ENROLL_TOKEN="$resolved"
        echo "Using access token from default local token path."
        return 0
    fi

    return 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enroll-token)
                ENROLL_TOKEN="${2:-}"
                shift 2
                ;;
            --enroll-endpoint)
                ENROLL_ENDPOINT="${2:-}"
                shift 2
                ;;
            --device-id)
                DEVICE_ID="${2:-}"
                shift 2
                ;;
            --local-host)
                LOCAL_HOST="${2:-}"
                shift 2
                ;;
            --local-port)
                LOCAL_PORT="${2:-}"
                shift 2
                ;;
            --enroll-timeout-sec)
                ENROLL_TIMEOUT="${2:-}"
                shift 2
                ;;
            --wss-url)
                WSS_URL="${2:-}"
                shift 2
                ;;
            --wss-path-prefix)
                WSS_PATH_PREFIX="${2:-}"
                shift 2
                ;;
            --wstunnel-version)
                WSTUNNEL_VERSION="${2:-}"
                shift 2
                ;;
            --operator-public-key)
                OPERATOR_PUBLIC_KEY="${2:-}"
                shift 2
                ;;
            --operator-ssh-public-key)
                OPERATOR_SSH_PUBLIC_KEY="${2:-}"
                shift 2
                ;;
            --auto-register)
                AUTO_REGISTER="${2:-}"
                shift 2
                ;;
            --env-file)
                ENV_FILE="${2:-}"
                shift 2
                ;;
            --sender-backend-cmd)
                SENDER_BACKEND_CMD="${2:-}"
                shift 2
                ;;
            --skip-restart)
                SKIP_RESTART="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done

    AUTO_REGISTER="$(normalize_bool "$AUTO_REGISTER")" || {
        echo "Invalid --auto-register value: $AUTO_REGISTER"
        exit 1
    }

    is_valid_port "$LOCAL_PORT" || {
        echo "Invalid --local-port value: $LOCAL_PORT"
        exit 1
    }
    is_valid_positive_int "$ENROLL_TIMEOUT" || {
        echo "Invalid --enroll-timeout-sec value: $ENROLL_TIMEOUT"
        exit 1
    }
    if [[ -n "$WSS_URL" && ! "$WSS_URL" =~ ^wss?:// ]]; then
        echo "Invalid --wss-url value: $WSS_URL"
        exit 1
    fi
    WSS_PATH_PREFIX="${WSS_PATH_PREFIX#/}"
    WSS_PATH_PREFIX="${WSS_PATH_PREFIX%/}"
    if [[ -n "$WSS_PATH_PREFIX" && "$WSS_PATH_PREFIX" =~ [[:space:]] ]]; then
        echo "Invalid --wss-path-prefix value: $WSS_PATH_PREFIX"
        exit 1
    fi
    if [[ -z "$WSTUNNEL_VERSION" ]]; then
        echo "Invalid --wstunnel-version value: $WSTUNNEL_VERSION"
        exit 1
    fi
}

resolve_wstunnel_release_arch() {
    local machine_arch="$1"
    case "$machine_arch" in
        x86_64|amd64)
            printf "amd64"
            return 0
            ;;
        aarch64|arm64)
            printf "arm64"
            return 0
            ;;
        armv7l|armv7*)
            printf "armv7"
            return 0
            ;;
        armv6l|armv6*)
            printf "armv6"
            return 0
            ;;
        i386|i686)
            printf "386"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

install_wstunnel_from_release() {
    local version=""
    local machine_arch=""
    local release_arch=""
    local asset_name=""
    local release_url=""
    local tmp_dir=""
    local tmp_tar=""
    local extracted_bin=""

    machine_arch="$(uname -m 2>/dev/null || true)"
    release_arch="$(resolve_wstunnel_release_arch "$machine_arch" || true)"
    [[ -n "$release_arch" ]] || return 1

    version="${WSTUNNEL_VERSION#v}"
    asset_name="wstunnel_${version}_linux_${release_arch}.tar.gz"
    release_url="https://github.com/erebe/wstunnel/releases/download/v${version}/${asset_name}"

    tmp_dir="$(mktemp -d /tmp/upri-wstunnel-release.XXXXXX)" || return 1
    tmp_tar="${tmp_dir}/${asset_name}"

    if ! curl -fsSL "$release_url" -o "$tmp_tar"; then
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        return 1
    fi

    if ! tar -xzf "$tmp_tar" -C "$tmp_dir"; then
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        return 1
    fi

    extracted_bin="$(find "$tmp_dir" -type f -name wstunnel | head -n 1)"
    if [[ -z "$extracted_bin" || ! -f "$extracted_bin" ]]; then
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        return 1
    fi

    if ! install -m 0755 "$extracted_bin" /usr/local/bin/wstunnel; then
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        return 1
    fi

    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    return 0
}

ensure_wstunnel_installed() {
    local installed_version=""
    local expected_version=""

    expected_version="${WSTUNNEL_VERSION#v}"

    if command -v wstunnel >/dev/null 2>&1; then
        installed_version="$(wstunnel --version 2>/dev/null | awk 'NR==1 {print $2}')"
        if [[ "$installed_version" == "$expected_version" ]]; then
            return 0
        fi
        echo "wstunnel version mismatch (found: ${installed_version:-unknown}, expected: $expected_version); reinstalling ..."
    fi

    echo "Installing wstunnel from GitHub release v${WSTUNNEL_VERSION#v} ..."

    if install_wstunnel_from_release; then
        echo "Installed wstunnel to /usr/local/bin/wstunnel."
        return 0
    fi

    return 1
}

validate_requirements() {
    local missing_commands=()

    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Run as root (use sudo)."
        exit 1
    fi

    if ! command -v "$SENDER_BACKEND_CMD" >/dev/null 2>&1; then
        echo "Unable to find sender-backend command: $SENDER_BACKEND_CMD"
        exit 1
    fi

    if ! ensure_wstunnel_installed; then
        missing_commands+=("wstunnel")
    fi
    if ! command -v ssh-keygen >/dev/null 2>&1; then
        missing_commands+=("ssh-keygen")
    fi
    if (( ${#missing_commands[@]} > 0 )); then
        echo "Missing required host command(s): ${missing_commands[*]}"
        echo "Install tunnel host packages, then rerun:"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install -y openssh-client"
        echo "  # ensure /usr/local/bin/wstunnel exists and is executable"
        exit 1
    fi

    if is_truthy "$AUTO_REGISTER"; then
        resolve_enroll_token_if_missing || {
            echo "Auto-register is enabled, but no enrollment token was found."
            echo "Provide --enroll-token or ensure sender access token exists (link/refresh first)."
            exit 1
        }
    fi
    resolve_operator_key_from_env_file_if_missing
}

backup_env_if_present() {
    local backup_path
    if [[ -f "$ENV_FILE" ]]; then
        backup_path="${ENV_FILE}.bak.$(date -u +%Y%m%d%H%M%S)"
        cp "$ENV_FILE" "$backup_path"
        echo "Backed up existing env file: $backup_path"
    fi
}

write_env_file() {
    local env_dir
    local tmp_file

    env_dir="$(dirname "$ENV_FILE")"
    mkdir -p "$env_dir"
    tmp_file="$(mktemp "/tmp/upri-sender-remote-tunnel-setup.XXXXXX")"

    {
        printf "# Managed by setup-remote-tunnel.sh\n"
        emit_env_line "REMOTE_TUNNEL_ENABLED" "true"
        emit_env_line "REMOTE_TUNNEL_AUTO_REGISTER_ENABLED" "$AUTO_REGISTER"
        emit_env_line "REMOTE_TUNNEL_ENROLL_TOKEN" "$ENROLL_TOKEN"
        emit_env_line "REMOTE_TUNNEL_ENROLL_ENDPOINT" "$ENROLL_ENDPOINT"
        emit_env_line "REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC" "$ENROLL_TIMEOUT"
        emit_env_line "REMOTE_TUNNEL_DEVICE_ID" "$DEVICE_ID"
        emit_env_line "REMOTE_TUNNEL_LOCAL_HOST" "$LOCAL_HOST"
        emit_env_line "REMOTE_TUNNEL_LOCAL_PORT" "$LOCAL_PORT"
        emit_env_line "REMOTE_TUNNEL_WSS_URL" "$WSS_URL"
        emit_env_line "REMOTE_TUNNEL_WSS_PATH_PREFIX" "$WSS_PATH_PREFIX"
        emit_env_line "REMOTE_TUNNEL_OPERATOR_PUBLIC_KEY" "$OPERATOR_PUBLIC_KEY"
        emit_env_line "REMOTE_TUNNEL_OPERATOR_SSH_PUBLIC_KEY" "$OPERATOR_SSH_PUBLIC_KEY"
    } > "$tmp_file"

    install -m 0600 "$tmp_file" "$ENV_FILE"
    rm -f "$tmp_file"

    echo "Wrote tunnel env file: $ENV_FILE"
}

install_and_start_service() {
    "$SENDER_BACKEND_CMD" INSTALL_REMOTE_TUNNEL_SERVICE

    if is_truthy "$SKIP_RESTART"; then
        echo "Skipped service restart (--skip-restart)."
        return 0
    fi

    systemctl restart "$SERVICE_NAME"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Remote tunnel service is active: $SERVICE_NAME"
    else
        echo "Remote tunnel service failed to become active: $SERVICE_NAME"
        systemctl --no-pager --full status "$SERVICE_NAME" || true
    fi
}

show_postcheck() {
    echo
    echo "Tunnel status:"
    "$SENDER_BACKEND_CMD" REMOTE_TUNNEL_STATUS || true
    echo
    echo "If auto-registration is enabled, check recent logs:"
    echo "  journalctl -u $SERVICE_NAME -n 80 --no-pager"
}

main() {
    parse_args "$@"
    validate_requirements
    backup_env_if_present
    write_env_file
    install_and_start_service
    show_postcheck
}

main "$@"
