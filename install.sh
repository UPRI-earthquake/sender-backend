#!/bin/bash
set -u

BACKEND_URL="https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/rshake-alerts/sender-backend.sh"
FRONTEND_URL="https://raw.githubusercontent.com/UPRI-earthquake/sender-frontend/rshake-alerts/sender-frontend.sh"
TUNNEL_SETUP_URL="https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/rshake-alerts/setup-remote-tunnel.sh"

INSTALL_DIR="/usr/local/bin"
HOST_SCRIPTS_DIR="${SENDER_HOST_SCRIPTS_DIR:-/opt/upri/host-scripts}"
BACKEND_PAYLOAD_PATH="${HOST_SCRIPTS_DIR}/sender-backend"
FRONTEND_PAYLOAD_PATH="${HOST_SCRIPTS_DIR}/sender-frontend"
TUNNEL_SETUP_PAYLOAD_PATH="${HOST_SCRIPTS_DIR}/setup-remote-tunnel"
REBOOT_POLICY_DEFAULT="on-failure"
REBOOT_POLICY="${SENDER_INSTALL_REBOOT_POLICY:-$REBOOT_POLICY_DEFAULT}"
START_RETRY_COUNT_DEFAULT=3
START_RETRY_DELAY_SEC_DEFAULT=4
START_RETRY_COUNT="${SENDER_INSTALL_START_RETRY_COUNT:-$START_RETRY_COUNT_DEFAULT}"
START_RETRY_DELAY_SEC="${SENDER_INSTALL_START_RETRY_DELAY_SEC:-$START_RETRY_DELAY_SEC_DEFAULT}"
WSTUNNEL_IMAGE_DEFAULT="ghcr.io/erebe/wstunnel:latest"
WSTUNNEL_IMAGE="${SENDER_INSTALL_WSTUNNEL_IMAGE:-$WSTUNNEL_IMAGE_DEFAULT}"
WSTUNNEL_BINARY_PATH_DEFAULT="/usr/local/bin/wstunnel"
WSTUNNEL_BINARY_PATH="${SENDER_INSTALL_WSTUNNEL_BINARY_PATH:-$WSTUNNEL_BINARY_PATH_DEFAULT}"

print_usage() {
    cat <<EOF
Usage: install.sh [--reboot-policy never|on-failure|always]

Options:
  --reboot-policy <value>  Reboot behavior after installation (default: on-failure)
                           never      : never reboot
                           on-failure : prompt reboot only if service/container startup fails
                           always     : reboot after successful install
  -h, --help               Show this help message

Environment overrides:
  SENDER_INSTALL_REBOOT_POLICY
  SENDER_INSTALL_START_RETRY_COUNT
  SENDER_INSTALL_START_RETRY_DELAY_SEC
  SENDER_INSTALL_WSTUNNEL_IMAGE
  SENDER_INSTALL_WSTUNNEL_BINARY_PATH
EOF
}

normalize_reboot_policy() {
    local raw="$1"
    case "$(echo "$raw" | tr '[:upper:]' '[:lower:]')" in
        never|on-failure|always)
            echo "$(echo "$raw" | tr '[:upper:]' '[:lower:]')"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reboot-policy)
                if [[ $# -lt 2 ]]; then
                    echo "Missing value for --reboot-policy"
                    print_usage
                    exit 1
                fi
                REBOOT_POLICY="$2"
                shift 2
                ;;
            --reboot-policy=*)
                REBOOT_POLICY="${1#*=}"
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    REBOOT_POLICY="$(normalize_reboot_policy "$REBOOT_POLICY")" || {
        echo "Invalid reboot policy: $REBOOT_POLICY"
        print_usage
        exit 1
    }

    if [[ ! "$START_RETRY_COUNT" =~ ^[0-9]+$ ]] || (( START_RETRY_COUNT < 1 )); then
        START_RETRY_COUNT="$START_RETRY_COUNT_DEFAULT"
    fi
    if [[ ! "$START_RETRY_DELAY_SEC" =~ ^[0-9]+$ ]] || (( START_RETRY_DELAY_SEC < 1 )); then
        START_RETRY_DELAY_SEC="$START_RETRY_DELAY_SEC_DEFAULT"
    fi
}

download_payload() {
    local url="$1"
    local destination="$2"

    sudo curl -fsSL "$url" -o "$destination" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to download payload script from $url"
        return 1
    }

    sudo chmod +x "$destination"
    echo -en "[  \e[32mOK\e[0m  ] "
    echo "Installed payload script at $destination"
    return 0
}

install_wrapper() {
    local wrapper_path="$1"
    local delegate_path="$2"
    local tmp_file

    tmp_file="$(mktemp /tmp/upri-wrapper.XXXXXX)" || return 1
    cat <<WRAP > "$tmp_file"
#!/bin/sh
exec "$delegate_path" "\$@"
WRAP

    sudo install -m 0755 "$tmp_file" "$wrapper_path" || {
        rm -f "$tmp_file" >/dev/null 2>&1
        return 1
    }

    rm -f "$tmp_file" >/dev/null 2>&1
    echo -en "[  \e[32mOK\e[0m  ] "
    echo "Installed wrapper $wrapper_path -> $delegate_path"
    return 0
}

install_wstunnel_binary_from_image() {
    local container_id=""
    local tmp_file=""

    container_id="$(docker create "$WSTUNNEL_IMAGE" 2>/dev/null)" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to create container from $WSTUNNEL_IMAGE for wstunnel install."
        return 1
    }

    tmp_file="$(mktemp /tmp/upri-wstunnel.XXXXXX)" || {
        docker rm -f "$container_id" >/dev/null 2>&1 || true
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to allocate temp file for wstunnel install."
        return 1
    }

    if ! docker cp "${container_id}:/home/app/wstunnel" "$tmp_file" >/dev/null 2>&1; then
        rm -f "$tmp_file" >/dev/null 2>&1
        docker rm -f "$container_id" >/dev/null 2>&1 || true
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to extract /home/app/wstunnel from $WSTUNNEL_IMAGE."
        return 1
    fi

    docker rm -f "$container_id" >/dev/null 2>&1 || true

    if ! sudo install -m 0755 "$tmp_file" "$WSTUNNEL_BINARY_PATH"; then
        rm -f "$tmp_file" >/dev/null 2>&1
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to install wstunnel to $WSTUNNEL_BINARY_PATH."
        return 1
    fi

    rm -f "$tmp_file" >/dev/null 2>&1
    if ! "$WSTUNNEL_BINARY_PATH" --version >/dev/null 2>&1; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "wstunnel installed but version check failed at $WSTUNNEL_BINARY_PATH."
        return 1
    fi

    echo -en "[  \e[32mOK\e[0m  ] "
    echo "Installed wstunnel at $WSTUNNEL_BINARY_PATH from $WSTUNNEL_IMAGE."
    return 0
}

ensure_wstunnel_installed() {
    local current_wstunnel
    current_wstunnel="$(command -v wstunnel 2>/dev/null || true)"

    if [[ -n "$current_wstunnel" ]] && "$current_wstunnel" --version >/dev/null 2>&1; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "wstunnel already installed at $current_wstunnel."
        return 0
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Docker is required to auto-install wstunnel."
        return 1
    fi

    install_wstunnel_binary_from_image
}

reboot_prompt_on_failure() {
    read -rp "Sender services failed to start cleanly. Reboot device now? (y/n): " choice
    case "$choice" in
        y|Y|yes|YES)
            sudo reboot
            ;;
        n|N|no|NO)
            echo "No reboot requested. You may reboot manually to recover services."
            ;;
        *)
            echo "Invalid choice. No reboot requested. You may reboot manually to recover services."
            ;;
    esac
}

containers_running() {
    [[ "$(docker inspect --format='{{.State.Running}}' sender-backend 2>/dev/null)" == "true" ]] \
      && [[ "$(docker inspect --format='{{.State.Running}}' sender-frontend 2>/dev/null)" == "true" ]]
}

start_and_verify_services() {
    local attempt=1

    while (( attempt <= START_RETRY_COUNT )); do
        sudo systemctl start sender-backend.service >/dev/null 2>&1 || true
        sudo systemctl start sender-frontend.service >/dev/null 2>&1 || true

        if containers_running; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Sender services are running (attempt $attempt/$START_RETRY_COUNT)."
            return 0
        fi

        if (( attempt < START_RETRY_COUNT )); then
            sleep "$START_RETRY_DELAY_SEC"
        fi
        ((attempt++))
    done

    echo -en "[\e[1;31mFAILED\e[0m] "
    echo "Sender services/containers failed health verification after $START_RETRY_COUNT attempts."
    return 1
}

apply_reboot_policy() {
    local install_status="$1"

    case "$REBOOT_POLICY" in
        never)
            if [[ "$install_status" != "ok" ]]; then
                echo "Reboot policy is 'never'. Please inspect and reboot manually if needed."
            fi
            return 0
            ;;
        on-failure)
            if [[ "$install_status" == "ok" ]]; then
                return 0
            fi
            if [[ -t 0 ]]; then
                reboot_prompt_on_failure
            else
                echo "Non-interactive install and startup failed. Reboot skipped by default."
                echo "Rerun with --reboot-policy always if automatic reboot is desired."
            fi
            return 0
            ;;
        always)
            echo "Reboot policy is 'always'. Rebooting now..."
            sudo reboot
            return 0
            ;;
    esac
}

main() {
    parse_args "$@"

    sudo mkdir -p "$HOST_SCRIPTS_DIR" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to prepare host script directory: $HOST_SCRIPTS_DIR"
        exit 1
    }

    download_payload "$BACKEND_URL" "$BACKEND_PAYLOAD_PATH" || exit 1
    download_payload "$FRONTEND_URL" "$FRONTEND_PAYLOAD_PATH" || exit 1
    download_payload "$TUNNEL_SETUP_URL" "$TUNNEL_SETUP_PAYLOAD_PATH" || exit 1

    install_wrapper "${INSTALL_DIR}/sender-backend" "$BACKEND_PAYLOAD_PATH" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to install sender-backend wrapper"
        exit 1
    }

    install_wrapper "${INSTALL_DIR}/sender-frontend" "$FRONTEND_PAYLOAD_PATH" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to install sender-frontend wrapper"
        exit 1
    }

    install_wrapper "${INSTALL_DIR}/sender-setup-remote-tunnel" "$TUNNEL_SETUP_PAYLOAD_PATH" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to install sender-setup-remote-tunnel wrapper"
        exit 1
    }

    sender-backend NETWORK_SETUP    && \
    sender-backend PULL             && \
    sender-backend CREATE           || {
        echo "Error in sender-backend container download/create. Aborting."
        exit 1
    }

    ensure_wstunnel_installed || {
        echo "Failed to install wstunnel prerequisite. Aborting."
        exit 1
    }

    sudo sender-backend INSTALL_SERVICE || {
        echo "Error in sender-backend service installation. Aborting."
        exit 1
    }

    sender-frontend PULL             && \
    sender-frontend CREATE           && \
    sudo sender-frontend INSTALL_SERVICE  || {
        echo "Error in sender-frontend container & service installation. Aborting."
        exit 1
    }

    if start_and_verify_services; then
        apply_reboot_policy "ok"
    else
        apply_reboot_policy "failed"
    fi
}

main "$@"
