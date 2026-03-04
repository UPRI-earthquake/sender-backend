#!/bin/sh

HOST_SCRIPTS_DIR="${SENDER_HOST_SCRIPTS_DIR:-/host-scripts}"
PAYLOAD_DIR="/opt/upri/scripts/payload"
LOCK_DIR="/tmp/upri-host-script-sync.lock"
LOCK_TIMEOUT_SEC="${SENDER_SCRIPT_SYNC_TIMEOUT_SEC:-20}"
BUNDLE_VERSION="${SENDER_IMAGE_BUNDLE_VERSION:-unknown}"
BUNDLE_TAG="${SENDER_BUNDLE_TAG:-latest}"
ALERT_ENDPOINT="${AUTO_UPDATE_ALERT_ENDPOINT:-https://earthquake.science.upd.edu.ph/api/messaging/restricted/rshake-alert}"
ALERT_TIMEOUT_SEC="${AUTO_UPDATE_ALERT_TIMEOUT_SEC:-8}"

log_info() {
  printf '[  \033[32mOK\033[0m  ] %s\n' "$1"
}

log_warn() {
  printf '[\033[1;33mWARN\033[0m] %s\n' "$1" >&2
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

sanitize_token() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/^-*//; s/-*$//'
}

read_device_value() {
  file_path="$1"
  if [ -r "$file_path" ]; then
    tr -d '\r' < "$file_path" | head -n 1 | xargs
    return 0
  fi
  printf ''
  return 1
}

post_sync_failure_alert() {
  reason="$1"

  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  network="$(read_device_value /opt/settings/sys/NET.txt)"
  station="$(read_device_value /opt/settings/sys/STN.txt)"
  stream_id="${network}_${station}_.*/MSEED"
  if [ -z "${network}${station}" ]; then
    stream_id="AUTO_UPDATE_SENDER"
  fi

  occurred_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if [ -r /proc/sys/kernel/random/uuid ]; then
    message_id="$(cat /proc/sys/kernel/random/uuid)"
  else
    message_id="$(date +%s)-$$"
  fi

  dedupe_key="auto-update.$(sanitize_token "${station:-$stream_id}").script-sync-failed"
  payload="{\"schemaVersion\":\"1.0\",\"messageId\":\"$(json_escape "$message_id")\",\"type\":\"device.alert\",\"occurredAt\":\"$(json_escape "$occurred_at")\",\"device\":{\"network\":\"$(json_escape "$network")\",\"station\":\"$(json_escape "$station")\",\"streamId\":\"$(json_escape "$stream_id")\"},\"status\":\"AUTO_UPDATE\",\"alertCode\":\"AUTO_UPDATE_SCRIPT_SYNC_FAILED\",\"severity\":\"warning\",\"summary\":\"Sender startup hook could not sync host scripts.\",\"details\":{\"source\":\"sender-startup-hook\",\"notificationScope\":\"admin-only\",\"bundleTag\":\"$(json_escape "$BUNDLE_TAG")\",\"bundleVersion\":\"$(json_escape "$BUNDLE_VERSION")\",\"targetDir\":\"$(json_escape "$HOST_SCRIPTS_DIR")\",\"reason\":\"$(json_escape "$reason")\"},\"dedupeKey\":\"$(json_escape "$dedupe_key")\"}"

  if [ -n "${RSHAKE_ALERT_SHARED_SECRET:-}" ]; then
    curl --silent --show-error --max-time "$ALERT_TIMEOUT_SEC" \
      -H "Content-Type: application/json" \
      -H "X-RShake-Alert-Secret: ${RSHAKE_ALERT_SHARED_SECRET}" \
      -X POST "$ALERT_ENDPOINT" \
      -d "$payload" >/dev/null 2>&1 || true
  else
    curl --silent --show-error --max-time "$ALERT_TIMEOUT_SEC" \
      -H "Content-Type: application/json" \
      -X POST "$ALERT_ENDPOINT" \
      -d "$payload" >/dev/null 2>&1 || true
  fi
}

acquire_lock() {
  elapsed=0
  while ! mkdir "$LOCK_DIR" >/dev/null 2>&1; do
    if [ "$elapsed" -ge "$LOCK_TIMEOUT_SEC" ]; then
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 0
}

release_lock() {
  rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
}

if [ ! -d "$PAYLOAD_DIR" ]; then
  log_warn "Host script payload directory missing: $PAYLOAD_DIR"
  post_sync_failure_alert "missing-payload-dir"
  exit 0
fi

if ! acquire_lock; then
  log_warn "Timed out waiting for host script sync lock."
  post_sync_failure_alert "lock-timeout"
  exit 0
fi

if ! mkdir -p "$HOST_SCRIPTS_DIR" >/dev/null 2>&1; then
  release_lock
  log_warn "Unable to create host scripts directory: $HOST_SCRIPTS_DIR"
  post_sync_failure_alert "mkdir-failed"
  exit 0
fi

marker_file="$HOST_SCRIPTS_DIR/.bundle-version"
need_update=0
if [ ! -x "$HOST_SCRIPTS_DIR/sender-backend" ] || [ ! -x "$HOST_SCRIPTS_DIR/sender-frontend" ]; then
  need_update=1
elif [ ! -r "$marker_file" ]; then
  need_update=1
else
  current_version="$(head -n 1 "$marker_file" | tr -d '\r' | xargs)"
  if [ "$current_version" != "$BUNDLE_VERSION" ]; then
    need_update=1
  fi
fi

if [ "$need_update" -eq 0 ]; then
  release_lock
  log_info "Host scripts already aligned with bundle version $BUNDLE_VERSION."
  exit 0
fi

if ! install -m 0755 "$PAYLOAD_DIR/sender-backend" "$HOST_SCRIPTS_DIR/sender-backend" >/dev/null 2>&1; then
  release_lock
  log_warn "Failed to install sender-backend payload script."
  post_sync_failure_alert "backend-install-failed"
  exit 0
fi

if ! install -m 0755 "$PAYLOAD_DIR/sender-frontend" "$HOST_SCRIPTS_DIR/sender-frontend" >/dev/null 2>&1; then
  release_lock
  log_warn "Failed to install sender-frontend payload script."
  post_sync_failure_alert "frontend-install-failed"
  exit 0
fi

printf '%s\n' "$BUNDLE_VERSION" > "$marker_file" 2>/dev/null || {
  release_lock
  log_warn "Failed to write bundle marker file."
  post_sync_failure_alert "marker-write-failed"
  exit 0
}

release_lock
log_info "Host scripts synchronized to bundle version $BUNDLE_VERSION."
exit 0
