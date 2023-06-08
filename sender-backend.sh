#!/bin/bash

# Constants
SERVICE="sender-backend.service"
UNIT_FILE="/lib/systemd/system/$SERVICE"
IMAGE="ghcr.io/upri-earthquake/sender-backend:0.0.1" #TODO: Change tag to :latest
CONTAINER="sender-backend"

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

function create_container() {
  if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "Container $CONTAINER already exists."
    return 0 # Success
  else
    docker create \
      --name "$CONTAINER" \
      --volume /sys/fs/cgroup:/sys/fs/cgroup:ro \ # work around for oci runtime error
      --volume /opt/settings:/opt/settings:ro \ # contains NET, STAT info
      --volume xxx:/app/slink2dali:ro \ # location of slink2dali executable
      "$IMAGE"

    if [[ $? -eq 0 ]]; then
      echo "Container $CONTAINER created successfully."
      return 0
    else
      echo "Failed to create container $CONTAINER."
      return 1
    fi

  fi
}

# function: start_container()
# TODO: check if container is running
# TODO: start container if it's not running
# TODO: check if container is successfully started
function start_container() {
  if docker container inspect --format="{{.State.Running}}" "$CONTAINER" >/dev/null 2>&1; then
    echo "Container $CONTAINER is already running."
  else
    docker start "$CONTAINER"
    if [[ $? -eq 0 ]]; then
      echo "Container $CONTAINER started successfully."
    else
      echo "Failed to start container $CONTAINER."
    fi
  fi
}

# function: stop_container()
# TODO: check if container is running
# TODO: stop container if it's running
# TODO: check if container is successfully stopped
function stop_container() {
  if docker container inspect --format="{{.State.Running}}" "$CONTAINER" >/dev/null 2>&1; then
    docker stop "$CONTAINER"
    if [[ $? -eq 0 ]]; then
      echo "Container $CONTAINER stopped successfully."
    else
      echo "Failed to stop container $CONTAINER."
    fi
  else
    echo "Container $CONTAINER is not running."
  fi
}

## execute function based on argument: INSTALL_SERVICE, PULL, CREATE, START, STOP
case $1 in
  "INSTALL_SERVICE")
    install_service
    ;;
  "PULL")
    pull_container
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
    echo "Invalid argument. Usage: ./script.sh [INSTALL_SERVICE|PULL|CREATE|START|STOP]"
    ;;
esac

# On install script
# get sender-backend, sender-frontend scripts
# install them on usr/local/bin
# call pull, create, install
# use postboot service for starting and stopping each container.service?

#myshake@raspberryshake:/opt$ cat /lib/systemd/system/raspberryshake.service
#[Unit]
#Description=Raspberry Shake Boot Script
#After=ntpd.service docker.service
#Wants=ntpd.service
#
#[Service]
#Type=oneshot
#User=myshake
#ExecStart=/usr/local/bin/postboot.rshake
#
#[Install]
#WantedBy=multi-user.target


