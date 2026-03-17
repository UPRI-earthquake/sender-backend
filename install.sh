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
WSTUNNEL_BINARY_PATH_DEFAULT="/usr/local/bin/wstunnel"
WSTUNNEL_BINARY_PATH="${SENDER_INSTALL_WSTUNNEL_BINARY_PATH:-$WSTUNNEL_BINARY_PATH_DEFAULT}"
WSTUNNEL_VERSION_DEFAULT="10.5.2"
WSTUNNEL_VERSION="${SENDER_INSTALL_WSTUNNEL_VERSION:-$WSTUNNEL_VERSION_DEFAULT}"

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
  SENDER_INSTALL_WSTUNNEL_BINARY_PATH
  SENDER_INSTALL_WSTUNNEL_VERSION
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

install_wstunnel_binary_from_release() {
    local release_arch=""
    local machine_arch=""
    local version=""
    local asset_name=""
    local release_url=""
    local tmp_dir=""
    local tmp_tar=""
    local extracted_bin=""

    machine_arch="$(uname -m 2>/dev/null || true)"
    release_arch="$(resolve_wstunnel_release_arch "$machine_arch" || true)"
    if [[ -z "$release_arch" ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Unsupported architecture for release fallback: ${machine_arch:-unknown}"
        return 1
    fi

    version="${WSTUNNEL_VERSION#v}"
    asset_name="wstunnel_${version}_linux_${release_arch}.tar.gz"
    release_url="https://github.com/erebe/wstunnel/releases/download/v${version}/${asset_name}"

    tmp_dir="$(mktemp -d /tmp/upri-wstunnel-release.XXXXXX)" || return 1
    tmp_tar="${tmp_dir}/${asset_name}"

    if ! curl -fsSL "$release_url" -o "$tmp_tar"; then
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to download wstunnel release asset: $release_url"
        return 1
    fi

    if ! tar -xzf "$tmp_tar" -C "$tmp_dir"; then
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to extract wstunnel release asset: $asset_name"
        return 1
    fi

    extracted_bin="$(find "$tmp_dir" -type f -name wstunnel | head -n 1)"
    if [[ -z "$extracted_bin" || ! -f "$extracted_bin" ]]; then
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Extracted release does not contain wstunnel binary."
        return 1
    fi

    if ! sudo install -m 0755 "$extracted_bin" "$WSTUNNEL_BINARY_PATH"; then
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to install wstunnel to $WSTUNNEL_BINARY_PATH."
        return 1
    fi

    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    if ! "$WSTUNNEL_BINARY_PATH" --version >/dev/null 2>&1; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "wstunnel installed from release but version check failed."
        return 1
    fi

    echo -en "[  \e[32mOK\e[0m  ] "
    echo "Installed wstunnel at $WSTUNNEL_BINARY_PATH from GitHub release v${version}."
    return 0
}

ensure_wstunnel_installed() {
    local current_wstunnel
    local installed_version=""
    local expected_version=""

    expected_version="${WSTUNNEL_VERSION#v}"
    current_wstunnel="$(command -v wstunnel 2>/dev/null || true)"

    if [[ -n "$current_wstunnel" ]] && "$current_wstunnel" --version >/dev/null 2>&1; then
        installed_version="$("$current_wstunnel" --version 2>/dev/null | awk 'NR==1 {print $2}')"
        if [[ "$installed_version" == "$expected_version" ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "wstunnel v$installed_version already installed at $current_wstunnel."
            return 0
        fi
        echo -en "[\e[1;33mWARN\e[0m] "
        echo "wstunnel version mismatch (found: ${installed_version:-unknown}, expected: $expected_version). Reinstalling."
    fi

    install_wstunnel_binary_from_release
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
