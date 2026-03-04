#!/bin/bash
set -u

INSTALL_DIR="/usr/local/bin"
HOST_SCRIPTS_DIR="${SENDER_HOST_SCRIPTS_DIR:-/opt/upri/host-scripts}"

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

sudo sender-backend UNINSTALL_SERVICE
sudo sender-frontend UNINSTALL_SERVICE

sudo rm -f "${INSTALL_DIR}/sender-backend"
sudo rm -f "${INSTALL_DIR}/sender-frontend"

sudo rm -f "${HOST_SCRIPTS_DIR}/sender-backend" "${HOST_SCRIPTS_DIR}/sender-frontend" "${HOST_SCRIPTS_DIR}/.bundle-version"
sudo rmdir "${HOST_SCRIPTS_DIR}" >/dev/null 2>&1 || true

if [[ -f "${INSTALL_DIR}/sender-backend" || -f "${INSTALL_DIR}/sender-frontend" ]]; then
    echo -en "[\e[1;31mFAILED\e[0m] "
    echo "Failed to remove one or both sender launchers from $INSTALL_DIR"
    exit 1
fi

echo -en "[  \e[32mOK\e[0m  ] "
echo "Sender launchers and host-script payloads removed successfully"
exit 0
