#!/bin/bash
INSTALL_DIR="/usr/local/bin"

# Check if sender-scripts exist in INSTALL_DIR
if [[ ! -f "$INSTALL_DIR/sender-backend" ]]; then
    echo "sender-backend script does not exist in $INSTALL_DIR"
    exit 1
fi
if [[ ! -f "$INSTALL_DIR/sender-frontend" ]]; then
    echo "sender-frontend script does not exist in $INSTALL_DIR"
    exit 1
fi

# Remove sender-backend and sender-frontend containers, images, network, & service
sender-backend STOP
sender-backend REMOVE_CONTAINER
sender-backend REMOVE_IMAGE

sender-frontend STOP
sender-frontend REMOVE_CONTAINER
sender-frontend REMOVE_IMAGE

sender-backend REMOVE_VOLUME
sender-backend REMOVE_NETWORK

sender-backend UNINSTALL_SERVICE
sender-frontend UNINSTALL_SERVICE

# Remove sender-backend and sender-frontend scripts from /usr/local/bin
sudo rm -f /usr/local/bin/sender-backend
sudo rm -f /usr/local/bin/sender-frontend

# Check if sender-backend and sender-frontend scripts are removed
if [[ -f "$INSTALL_DIR/sender-backend" || -f "$INSTALL_DIR/sender-frontend" ]]; then
    echo "Failed to remove one or both sender scripts from $INSTALL_DIR"
    exit 1
else
    echo "Both sender-backend and sender-frontend scripts successfully removed from $INSTALL_DIR"
    exit 0
fi
