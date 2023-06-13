#!/bin/bash

# Download sender-backend.sh and sender-frontend.sh sh-scripts from GitHub 
BACKEND_URL= "https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/dockerize/sender-backend.sh?token=GHSAT0AAAAAAB7VZD57NBJORDJOOLFR3PEIZEICYGA"
FRONTEND_URL=""

# Install sender-backend and sender-frontend into /usr/local/bin directory
INSTALL_DIR="/usr/local/bin"

# Function to download and install a script
download_and_install_script() {
    local url=$1 script_name=$2

    # Download the script
    curl -sSL "$url" -o "$INSTALL_DIR/$script_name" || {
        echo "Failed to download script: $script_name"
        exit 1
    }

    chmod +x "$INSTALL_DIR/$script_name" # Make the script executable
}

# Download and install the backend script
download_and_install_script "$BACKEND_URL" "sender-backend"

# Download and install the frontend script
#download_and_install_script "$FRONTEND_URL" "sender-frontend"

# sender-backend container & service installation
sender-backend PULL             && \
sender-backend NETWORK_SETUP    && \
sender-backend CREATE           && \
sender-backend INSTALL_SERVICE  || {
    echo "Error in sender-backend container download & service installation. Aborting."
    exit 1
}

# sender-frontend container & service installation
#sender-frontend PULL             && \
#sender-frontend NETWORK_SETUP    && \
#sender-frontend CREATE           && \
#sender-frontend INSTALL_SERVICE  || {
#    echo "Error in sender-frontend container & service installation. Aborting."
#    exit 1
#}



# get postboot script, install on usr/local/bin
# install and enable postboot service
