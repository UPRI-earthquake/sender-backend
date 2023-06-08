#!/bin/bash

# Constants
SERVICE="sender-backend.service"
UNIT_FILE="/lib/systemd/system/$SERVICE"

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


