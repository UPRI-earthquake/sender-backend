#!/bin/bash

# Download sender-backend.sh and sender-frontend.sh sh-scripts from GitHub
BACKEND_URL="192.168.1.13:9999/sender-backend/sender-backend.sh"
FRONTEND_URL="192.168.1.13:9999/sender-frontend/sender-frontend.sh"

# Install sender-backend and sender-frontend into /usr/local/bin directory
INSTALL_DIR="/usr/local/bin"

# Function to download and install a script
download_and_install_script() {
    local url=$1 script_name=$2

    # Download the script
    sudo curl -sSL "$url" -o "$INSTALL_DIR/$script_name" || {
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to download script: $script_name"
        exit 1
    }

    sudo chmod +x "$INSTALL_DIR/$script_name" # Make the script executable
    echo -en "[  \e[32mOK\e[0m  ] "
    echo "$script_name successfully downloaded and installed"
    return 0
}

# Download and install the backend script
download_and_install_script "$BACKEND_URL" "sender-backend"

# Download and install the frontend script
download_and_install_script "$FRONTEND_URL" "sender-frontend"

# sender-backend container & service installation
sender-backend NETWORK_SETUP    && \
sender-backend PULL             && \
sender-backend CREATE           && \
sudo sender-backend INSTALL_SERVICE  || {
    echo "Error in sender-backend container download & service installation. Aborting."
    exit 1
}

# sender-frontend container & service installation
sender-frontend PULL             && \
sender-frontend CREATE           && \
sudo sender-frontend INSTALL_SERVICE  || {
    echo "Error in sender-frontend container & service installation. Aborting."
    exit 1
}

# start services
if ! systemctl is-active --quiet sender-backend.service; then
    sudo systemctl start sender-backend.service || {
        echo "Error in starting sender-backend service. Aborting."
        exit 1
    }
    echo "sender-backend service started successfully."
else
    echo "sender-backend service is already running."
fi

if ! systemctl is-active --quiet sender-frontend.service; then
    sudo systemctl start sender-frontend.service || {
        echo "Error in starting sender-frontend service. Aborting."
        exit 1
    }
    echo "sender-frontend service started successfully."
else
    echo "sender-frontend service is already running."
fi

