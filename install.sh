#!/bin/bash

# Download sender-backend.sh and sender-frontend.sh sh-scripts from GitHub
BACKEND_URL="https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/sender-improvements/sender-backend.sh"
FRONTEND_URL="https://raw.githubusercontent.com/UPRI-earthquake/sender-frontend/sender-improvements/sender-frontend.sh"
PREINSTALL_URL="https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/sender-improvements/preinstall-health-check.sh"

# Install sender-backend and sender-frontend into /usr/local/bin directory
INSTALL_DIR="/usr/local/bin"

run_preinstall_health_check() {
    echo "Running pre-install health check..."
    if ! bash <(curl -fsSL "$PREINSTALL_URL"); then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Pre-install health check failed. Fix the issues above and re-run the installer."
        exit 1
    fi
}

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

# Prompt for rebooting the device
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

run_preinstall_health_check

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

# Prompt for reboot to start the new services
prompt_reboot
