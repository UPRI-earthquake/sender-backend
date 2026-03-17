#!/bin/bash
set -u

INSTALL_DIR="/usr/local/bin"
HOST_SCRIPTS_DIR="${SENDER_HOST_SCRIPTS_DIR:-/opt/upri/host-scripts}"
WSTUNNEL_BINARY_PATH_DEFAULT="/usr/local/bin/wstunnel"
WSTUNNEL_BINARY_PATH="${SENDER_INSTALL_WSTUNNEL_BINARY_PATH:-$WSTUNNEL_BINARY_PATH_DEFAULT}"
REMOTE_TUNNEL_ENV_FILE="${REMOTE_TUNNEL_ENV_FILE:-/etc/upri/sender-remote-tunnel.env}"
REMOTE_TUNNEL_KEY_DIR="${REMOTE_TUNNEL_KEY_DIR:-/etc/upri/remote-tunnel}"
PURGE_PREREQS="false"

usage() {
    cat <<EOF
Usage: uninstall.sh [--purge-prereqs]

Options:
  --purge-prereqs   Also remove tunnel host prerequisites:
                    - $WSTUNNEL_BINARY_PATH
                    - $REMOTE_TUNNEL_ENV_FILE
                    - $REMOTE_TUNNEL_KEY_DIR
  -h, --help        Show this help message

Default behavior keeps prerequisites installed for faster reinstall.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --purge-prereqs)
                PURGE_PREREQS="true"
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
}

purge_prereqs() {
    local failed=0

    if sudo rm -f "$WSTUNNEL_BINARY_PATH"; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Removed wstunnel binary at $WSTUNNEL_BINARY_PATH (if present)."
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to remove $WSTUNNEL_BINARY_PATH."
        failed=1
    fi

    if sudo rm -f "$REMOTE_TUNNEL_ENV_FILE"; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Removed remote tunnel env file at $REMOTE_TUNNEL_ENV_FILE (if present)."
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to remove $REMOTE_TUNNEL_ENV_FILE."
        failed=1
    fi

    if sudo rm -rf "$REMOTE_TUNNEL_KEY_DIR"; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Removed remote tunnel key dir at $REMOTE_TUNNEL_KEY_DIR (if present)."
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to remove $REMOTE_TUNNEL_KEY_DIR."
        failed=1
    fi

    if [[ $failed -eq 1 ]]; then
        return 1
    fi
    return 0
}

parse_args "$@"

if [[ ! -f "${INSTALL_DIR}/sender-backend" ]]; then
    echo -en "[\e[1;31mFAILED\e[0m] "
    echo "sender-backend launcher does not exist in $INSTALL_DIR"
    exit 1
fi
if [[ ! -f "${INSTALL_DIR}/sender-frontend" ]]; then
    echo -en "[\e[1;31mFAILED\e[0m] "
    echo "sender-frontend launcher does not exist in $INSTALL_DIR"
    exit 1
fi

sender-backend STOP
sender-backend REMOVE_CONTAINER
sender-backend REMOVE_IMAGE

sender-frontend STOP
sender-frontend REMOVE_CONTAINER
sender-frontend REMOVE_IMAGE

sender-backend REMOVE_VOLUME
sender-backend REMOVE_NETWORK

sudo sender-backend REMOTE_TUNNEL_STOP || true
sudo sender-backend UNINSTALL_SERVICE
sudo sender-frontend UNINSTALL_SERVICE

sudo rm -f "${INSTALL_DIR}/sender-backend"
sudo rm -f "${INSTALL_DIR}/sender-frontend"
sudo rm -f "${INSTALL_DIR}/sender-setup-remote-tunnel"

sudo rm -f "${HOST_SCRIPTS_DIR}/sender-backend" "${HOST_SCRIPTS_DIR}/sender-frontend" "${HOST_SCRIPTS_DIR}/setup-remote-tunnel" "${HOST_SCRIPTS_DIR}/.bundle-version"
sudo rmdir "${HOST_SCRIPTS_DIR}" >/dev/null 2>&1 || true

if [[ -f "${INSTALL_DIR}/sender-backend" || -f "${INSTALL_DIR}/sender-frontend" || -f "${INSTALL_DIR}/sender-setup-remote-tunnel" ]]; then
    echo -en "[\e[1;31mFAILED\e[0m] "
    echo "Failed to remove one or more sender launchers from $INSTALL_DIR"
    exit 1
fi

if [[ "$PURGE_PREREQS" == "true" ]]; then
    purge_prereqs || exit 1
fi

echo -en "[  \e[32mOK\e[0m  ] "
echo "Sender launchers and host-script payloads removed successfully"
exit 0
