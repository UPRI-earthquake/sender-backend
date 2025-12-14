#!/bin/bash

# Constants
SERVICE="sender-backend.service"
UNIT_FILE="/lib/systemd/system/$SERVICE"
IMAGE="ghcr.io/upri-earthquake/sender-backend:latest"
CONTAINER="sender-backend"
VOLUME="UPRI-volume"
DOCKER_NETWORK="UPRI-docker-network"
UPDATE_SERVICE="sender-backend-update.service"
UPDATE_TIMER="sender-backend-update.timer"
UPDATE_SERVICE_FILE="/lib/systemd/system/$UPDATE_SERVICE"
UPDATE_TIMER_FILE="/lib/systemd/system/$UPDATE_TIMER"

## INSTALLATION FUNCTIONS

function install_service() {
    # Check if unit-file exists
    if [[ -f "$UNIT_FILE" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Unit file $UNIT_FILE already exists."
        install_update_timer
        return $?
    else
    # Write unit-file
        cat <<EOF > "$UNIT_FILE"
[Unit]
Description=UPRI: Sender Backend Service
After=docker.service raspberryshake.service
Requires=docker.service raspberryshake.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=myshake
ExecStart=/usr/local/bin/sender-backend START
ExecStop=/usr/local/bin/sender-backend STOP

[Install]
WantedBy=multi-user.target
EOF
      echo "Unit file $UNIT_FILE written."

      # Check if unit-file is successfully written as a disabled service
      systemctl daemon-reload
      systemctl --quiet enable "$SERVICE" >/dev/null 2>&1
      if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "$SERVICE installed as an enabled service."
          install_update_timer
          return $?
      else
          echo -en "[\e[1;31mFAILED\e[0m] "
          echo "Something went wrong in installing $SERVICE."
          return 1  # Failure
      fi
    fi
}

function install_update_timer() {
    local service_written=0
    local timer_written=0

    if [[ -f "$UPDATE_SERVICE_FILE" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Unit file $UPDATE_SERVICE_FILE already exists."
    else
        cat <<EOF > "$UPDATE_SERVICE_FILE"
[Unit]
Description=UPRI: Sender Stack Auto-update Service
ConditionPathExists=/usr/local/bin/sender-backend
ConditionPathExists=/usr/local/bin/sender-frontend
Wants=docker.service network-online.target
After=docker.service network-online.target

[Service]
Type=oneshot
User=myshake
ExecStart=/usr/bin/env bash -c '/usr/local/bin/sender-backend UPDATE; backend=\$?; /usr/local/bin/sender-frontend UPDATE; frontend=\$?; exit \$(( backend || frontend ))'

[Install]
WantedBy=multi-user.target
EOF
        echo "Unit file $UPDATE_SERVICE_FILE written."
        service_written=1
    fi

    if [[ -f "$UPDATE_TIMER_FILE" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Unit file $UPDATE_TIMER_FILE already exists."
    else
        cat <<EOF > "$UPDATE_TIMER_FILE"
[Unit]
Description=UPRI: Sender Stack Auto-update Timer

[Timer]
OnBootSec=15m
OnUnitActiveSec=1d
RandomizedDelaySec=30m
Unit=$UPDATE_SERVICE
Persistent=true

[Install]
WantedBy=timers.target
EOF
        echo "Unit file $UPDATE_TIMER_FILE written."
        timer_written=1
    fi

    systemctl daemon-reload
    if systemctl enable --now "$UPDATE_TIMER" >/dev/null 2>&1; then
        echo -en "[  \e[32mOK\e[0m  ] "
        if [[ $timer_written -eq 1 ]]; then
            echo "$UPDATE_TIMER installed, enabled, and started."
        else
            echo "$UPDATE_TIMER already enabled; ensured it is running."
        fi
        return 0
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to enable or start $UPDATE_TIMER."
        return 1
    fi
}

function uninstall_update_timer() {
    local removed=0

    systemctl stop "$UPDATE_TIMER" >/dev/null 2>&1
    systemctl disable "$UPDATE_TIMER" >/dev/null 2>&1

    if [[ -f "$UPDATE_TIMER_FILE" ]]; then
        rm "$UPDATE_TIMER_FILE"
        removed=1
    fi

    if [[ -f "$UPDATE_SERVICE_FILE" ]]; then
        rm "$UPDATE_SERVICE_FILE"
        removed=1
    fi

    systemctl daemon-reload

    echo -en "[  \e[32mOK\e[0m  ] "
    if [[ $removed -eq 1 ]]; then
        echo "Auto-update timer removed."
    else
        echo "Auto-update timer already removed."
    fi
    return 0
}

function pull_container() {
    docker pull "$IMAGE"
    if [[ $? -eq 0 ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Image $IMAGE pulled successfully."
        return 0
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to pull image $IMAGE."
        return 1
    fi
}

function create_network() {
    if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Docker network $DOCKER_NETWORK already exists."
        return 0 # Success
    else
        # create network
        docker network create \
            --driver bridge \
            --subnet 172.18.0.0/16 \
            --gateway 172.18.0.1 \
            --ip-range 172.18.0.0/24 \
            "$DOCKER_NETWORK"

        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Network $DOCKER_NETWORK created successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to create network $DOCKER_NETWORK."
            return 1
        fi

    fi
}

function create_container() {
    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER already exists."
        return 0 # Success
    else
        # get IP of rshake accessible from within the container
        local host_ip=`ip addr show docker0 | grep -Po 'inet \K[\d.]+' | head -n 1`
        # set domain name on which host_ip will be accessible from within container
        local in_docker_hostname="docker-host"
        # create container
        # TODO: Change W1_PROD_IP to earthquake-hub domain /api (for production)
        docker create \
            --name "$CONTAINER" \
            --add-host "$in_docker_hostname:$host_ip" \
            --volume /sys/fs/cgroup:/sys/fs/cgroup:ro \
            --volume /opt/settings:/opt/settings:ro \
            --volume "$VOLUME":/app/localDBs \
            --env LOCALDBS_DIRECTORY=/app/localDBs \
            --env W1_PROD_IP=earthquake.science.upd.edu.ph/api \
            --log-driver json-file \
            --log-opt max-size=10m \
            --log-opt max-file=3 \
            --net UPRI-docker-network \
            "$IMAGE"
            # 1st volume: workaround for docker's oci runtime error
            # 2nd volume: contains NET and STAT info
            # 3rd volume: will contain local file storage of sender-backend server
            # net should make sender-backend be accessible by name from frontend

        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container $CONTAINER created successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to create container $CONTAINER."
            return 1
        fi
    fi
}

function start_container() {
    if [[ $(docker inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null) == "true" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER is already running."
        return 0
    else
        docker start "$CONTAINER"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container $CONTAINER started successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to start container $CONTAINER."
            return 1
        fi
    fi
}

function update_container() {
    stop_container
    remove_container
    pull_container || return 1
    create_network
    create_container
    start_container
}

## UNINSTALL FUNCTIONS
function stop_container() {
    if [[ $(docker inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null) == "true" ]]; then
        docker stop "$CONTAINER"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container $CONTAINER stopped successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to stop container $CONTAINER."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER is not running."
        return 0
    fi
}

function remove_container() {
    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        docker rm "$CONTAINER"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Container $CONTAINER removed successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove container $CONTAINER."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Container $CONTAINER does not exist."
        return 0
    fi
}

function remove_image() {
    if docker inspect "$IMAGE" >/dev/null 2>&1; then
        docker rmi "$IMAGE"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Image $IMAGE removed successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove image $IMAGE."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Image $IMAGE does not exist."
        return 0
    fi
}

function remove_volume() {
    if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
        docker volume rm "$VOLUME"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Volume $VOLUME removed successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove volume $VOLUME."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Volume $VOLUME does not exist."
        return 0
    fi
}

function remove_network() {
    if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
        docker network rm "$DOCKER_NETWORK"
        if [[ $? -eq 0 ]]; then
            echo -en "[  \e[32mOK\e[0m  ] "
            echo "Network $DOCKER_NETWORK removed successfully."
            return 0
        else
            echo -en "[\e[1;31mFAILED\e[0m] "
            echo "Failed to remove network $DOCKER_NETWORK."
            return 1
        fi
    else
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Network $DOCKER_NETWORK does not exist."
        return 0
    fi
}

function uninstall_service() {
    if [[ ! -f "$UNIT_FILE" ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "Unit file $UNIT_FILE does not exist."
        uninstall_update_timer
        return $?
    fi

    sudo systemctl --quiet stop "$SERVICE" >/dev/null 2>&1
    if [[ $? -eq 1 ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to stop service $UNIT_FILE."
        return 1
    fi

    sudo systemctl --quiet disable "$SERVICE" >/dev/null 2>&1
    if [[ $? -eq 1 ]]; then
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to disable service $UNIT_FILE."
        return 1
    fi

    sudo rm "$UNIT_FILE"
    if [[ $? -eq 0 ]]; then
        echo -en "[  \e[32mOK\e[0m  ] "
        echo "$SERVICE uninstalled successfully."
        uninstall_update_timer
        return $?
    else
        echo -en "[\e[1;31mFAILED\e[0m] "
        echo "Failed to remove unit file $UNIT_FILE."
        return 1
    fi
}

## execute function based on argument: INSTALL_SERVICE, NETWORK_SETUP, PULL, CREATE, START, STOP
case $1 in
    "INSTALL_SERVICE")
        install_service
        ;;
    "PULL")
        pull_container
        ;;
    "NETWORK_SETUP")
        create_network
        ;;
    "CREATE")
        create_container
        ;;
    "START")
        start_container
        ;;
    "UPDATE")
        update_container
        ;;
    "STOP")
        stop_container
        ;;
    "REMOVE_CONTAINER")
        remove_container
        ;;
    "REMOVE_IMAGE")
        remove_image
        ;;
    "REMOVE_VOLUME")
        remove_volume
        ;;
    "REMOVE_NETWORK")
        remove_network
        ;;
    "UNINSTALL_SERVICE")
        uninstall_service
        ;;
    "INSTALL_UPDATE_TIMER")
        install_update_timer
        ;;
    "UNINSTALL_UPDATE_TIMER")
        uninstall_update_timer
        ;;
    *)
        echo "Invalid argument. Usage: ./script.sh [INSTALL_SERVICE|INSTALL_UPDATE_TIMER|NETWORK_SETUP|PULL|CREATE|START|STOP|UPDATE|REMOVE_NETWORK|REMOVE_VOLUME|REMOVE_IMAGE|REMOVE_CONTAINER|UNINSTALL_SERVICE|UNINSTALL_UPDATE_TIMER]"
        ;;
esac
