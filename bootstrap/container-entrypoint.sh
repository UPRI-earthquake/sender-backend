#!/bin/sh

if [ "${SENDER_SCRIPT_SYNC_MODE:-fallback}" = "fallback" ]; then
  /opt/upri/scripts/sync-host-scripts.sh || true
fi

exec dumb-init "$@"
