#!/bin/bash
set -u

BACKEND_URL="https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/main/sender-backend.sh"
FRONTEND_URL="https://raw.githubusercontent.com/UPRI-earthquake/sender-frontend/main/sender-frontend.sh"

INSTALL_DIR="/usr/local/bin"
HOST_SCRIPTS_DIR="${SENDER_HOST_SCRIPTS_DIR:-/opt/upri/host-scripts}"
BACKEND_PAYLOAD_PATH="${HOST_SCRIPTS_DIR}/sender-backend"
FRONTEND_PAYLOAD_PATH="${HOST_SCRIPTS_DIR}/sender-frontend"

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

prompt_reboot() {
    read -rp "Reboot rshake device to apply the changes? (y/n): " choice
    case "$choice" in
        y|Y|yes|YES)
            sudo reboot
            ;;
        n|N|no|NO)
            echo "No reboot requested. Changes will not take effect until the device is rebooted."
            ;;
        *)
            echo "Invalid choice. No reboot requested. Changes will not take effect until the device is rebooted."
            ;;
    esac
}

main() {
    sudo mkdir -p "$HOST_SCRIPTS_DIR" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to prepare host script directory: $HOST_SCRIPTS_DIR"
        exit 1
    }

    download_payload "$BACKEND_URL" "$BACKEND_PAYLOAD_PATH" || exit 1
    download_payload "$FRONTEND_URL" "$FRONTEND_PAYLOAD_PATH" || exit 1

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

    sender-backend NETWORK_SETUP    && \
    sender-backend PULL             && \
    sender-backend CREATE           && \
    sudo sender-backend INSTALL_SERVICE  || {
        echo "Error in sender-backend container download & service installation. Aborting."
        exit 1
    }

    sender-frontend PULL             && \
    sender-frontend CREATE           && \
    sudo sender-frontend INSTALL_SERVICE  || {
        echo "Error in sender-frontend container & service installation. Aborting."
        exit 1
    }

    prompt_reboot
}

main
