#!/bin/bash

# Constants
SERVICE="sender-backend.service"
UNIT_FILE="/lib/systemd/system/$SERVICE"
IMAGE="ghcr.io/upri-earthquake/sender-backend:0.0.2" #TODO: Change tag to :latest
CONTAINER="sender-backend"
DOCKER_NETWORK="UPRI-docker-network"

function install_service() {
  # Check if unit-file exists
  if [[ -f "$UNIT_FILE" ]]; then
    echo "Unit file $UNIT_FILE already exists."
  else
  # Write unit-file
    cat <<EOF > "$UNIT_FILE"
[Unit]
Description=UPRI: Sender Backend Service
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/sender-backend START
ExecStop=/usr/local/bin/sender-backend STOP

[Install]
WantedBy=multi-user.target
EOF
    echo "Unit file $UNIT_FILE written."

    # Check if unit-file is successfully written as a disabled service
    systemctl daemon-reload
    systemctl --quiet disable "$SERVICE" >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      echo "$SERVICE installed as a disabled service."
      return 0  # Success
    else
      echo "Something went wrong in installing $SERVICE."
      return 1  # Failure
    fi
  fi
}

function pull_container() {
  if docker inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Image $IMAGE already exists."
    return 0 # Success
  else
    docker pull "$IMAGE"
    if [[ $? -eq 0 ]]; then
      echo "Image $IMAGE pulled successfully."
      return 0
    else
      echo "Failed to pull image $IMAGE."
      return 1
    fi
  fi
}

function create_network() {
  if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
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
    # 1st volume: workaround for docker's oci runtime error
    # 2nd volume: contains NET and STAT info
    # 3rd volume: will contain local file storage of sender-backend server

    if [[ $? -eq 0 ]]; then
      echo "Network $DOCKER_NETWORK created successfully."
      return 0
    else
      echo "Failed to create network $DOCKER_NETWORK."
      return 1
    fi

  fi
}

function create_container() {
  if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "Container $CONTAINER already exists."
    return 0 # Success
  else
    # get IP of rshake accessible from within the container
    local host_ip=`ip addr show docker0 | grep -Po 'inet \K[\d.]+'`
    # set domain name on which host_ip will be accessible from within container
    local in_docker_hostname="docker-host"
    # create container
    docker create \
      --name "$CONTAINER" \
      --add-host $in_docker_hostname:$host_ip \
      --volume /sys/fs/cgroup:/sys/fs/cgroup:ro \
      --volume /opt/settings:/opt/settings:ro \
      --volume UPRI-volume:/app/localDBs \
      --net UPRI-docker-network \
      "$IMAGE"
    # 1st volume: workaround for docker's oci runtime error
    # 2nd volume: contains NET and STAT info
    # 3rd volume: will contain local file storage of sender-backend server

    if [[ $? -eq 0 ]]; then
      echo "Container $CONTAINER created successfully."
      return 0
    else
      echo "Failed to create container $CONTAINER."
      return 1
    fi

  fi
}

function start_container() {
  if [[ $(docker container inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null) == "true" ]]; then
    echo "Container $CONTAINER is already running."
  else
    docker start "$CONTAINER"
    if [[ $? -eq 0 ]]; then
      echo "Container $CONTAINER started successfully."
      return 0
    else
      echo "Failed to start container $CONTAINER."
      return 1
    fi
  fi
}

function stop_container() {
  if [[ $(docker container inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null) == "true" ]]; then
    docker stop "$CONTAINER"
    if [[ $? -eq 0 ]]; then
      echo "Container $CONTAINER stopped successfully."
      return 0
    else
      echo "Failed to stop container $CONTAINER."
      return 1
    fi
  else
    echo "Container $CONTAINER is not running."
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
  "STOP")
    stop_container
    ;;
  *)
    echo "Invalid argument. Usage: ./script.sh [INSTALL_SERVICE|NETWORK_SETUP|PULL|CREATE|START|STOP]"
    ;;
esac



