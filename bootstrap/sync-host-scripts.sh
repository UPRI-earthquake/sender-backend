#!/bin/sh

HOST_SCRIPTS_DIR="${SENDER_HOST_SCRIPTS_DIR:-/host-scripts}"
PAYLOAD_DIR="/opt/upri/scripts/payload"
BUNDLE_VERSION_FILE="/opt/upri/scripts/bundle-version"
LOCK_DIR="/tmp/upri-host-script-sync.lock"
LOCK_TIMEOUT_SEC="${SENDER_SCRIPT_SYNC_TIMEOUT_SEC:-20}"
BUNDLE_VERSION="${SENDER_IMAGE_BUNDLE_VERSION:-unknown}"
BUNDLE_TAG="${SENDER_BUNDLE_TAG:-latest}"
ALERT_ENDPOINT="${AUTO_UPDATE_ALERT_ENDPOINT:-https://earthquake.up.edu.ph/api/messaging/restricted/rshake-alert}"
ALERT_TIMEOUT_SEC="${AUTO_UPDATE_ALERT_TIMEOUT_SEC:-8}"
ALERT_RUNTIME_ENV_FILE="${RSHAKE_ALERT_RUNTIME_ENV_FILE:-/opt/upri/runtime/alert.env}"

if [ -r "$BUNDLE_VERSION_FILE" ]; then
  file_bundle_version="$(head -n 1 "$BUNDLE_VERSION_FILE" | tr -d '\r' | xargs)"
  if [ -n "$file_bundle_version" ] && [ "$file_bundle_version" != "unknown" ]; then
    BUNDLE_VERSION="$file_bundle_version"
  fi
fi

if [ -z "${RSHAKE_ALERT_SHARED_SECRET:-}" ] && [ -r "$ALERT_RUNTIME_ENV_FILE" ]; then
  RSHAKE_ALERT_SHARED_SECRET="$(
    sed -n 's/^RSHAKE_ALERT_SHARED_SECRET=//p' "$ALERT_RUNTIME_ENV_FILE" | head -n 1
  )"
fi

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

post_alert_payload() {
  payload="$1"
  alert_label="$2"

  if ! command -v curl >/dev/null 2>&1; then
    log_warn "curl is unavailable; skipping $alert_label alert post."
    return 0
  fi

  response_file="$(mktemp /tmp/upri-rshake-alert-response.XXXXXX)" || return 1
  error_file="$(mktemp /tmp/upri-rshake-alert-error.XXXXXX)" || {
    rm -f "$response_file" >/dev/null 2>&1
    return 1
  }

  if [ -n "${RSHAKE_ALERT_SHARED_SECRET:-}" ]; then
    http_code="$(curl --silent --show-error --max-time "$ALERT_TIMEOUT_SEC" \
      -H "Content-Type: application/json" \
      -H "X-RShake-Alert-Secret: ${RSHAKE_ALERT_SHARED_SECRET}" \
      -X POST "$ALERT_ENDPOINT" \
      -d "$payload" \
      -o "$response_file" \
      -w "%{http_code}" 2>"$error_file")"
    curl_exit=$?
  else
    http_code="$(curl --silent --show-error --max-time "$ALERT_TIMEOUT_SEC" \
      -H "Content-Type: application/json" \
      -X POST "$ALERT_ENDPOINT" \
      -d "$payload" \
      -o "$response_file" \
      -w "%{http_code}" 2>"$error_file")"
    curl_exit=$?
  fi

  case "$http_code" in
    2??)
      if [ "$curl_exit" -eq 0 ]; then
        rm -f "$response_file" "$error_file" >/dev/null 2>&1
        return 0
      fi
      ;;
  esac

  response_body="$(head -c 300 "$response_file" 2>/dev/null | tr '\r\n' '  ' | xargs 2>/dev/null || true)"
  error_body="$(head -c 300 "$error_file" 2>/dev/null | tr '\r\n' '  ' | xargs 2>/dev/null || true)"
  if [ "$curl_exit" -ne 0 ]; then
    log_warn "Failed to post $alert_label alert (curl exit $curl_exit${error_body:+: $error_body})."
  else
    log_warn "Failed to post $alert_label alert (HTTP ${http_code:-unknown}${response_body:+: $response_body})."
  fi

  rm -f "$response_file" "$error_file" >/dev/null 2>&1
  return 1
}

post_sync_failure_alert() {
  reason="$1"

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

  post_alert_payload "$payload" "script-sync-failed" || true
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

payload_differs() {
  payload_name="$1"
  payload_path="$PAYLOAD_DIR/$payload_name"
  target_path="$HOST_SCRIPTS_DIR/$payload_name"

  if [ ! -f "$payload_path" ]; then
    return 1
  fi
  if [ ! -x "$target_path" ]; then
    return 0
  fi
  ! cmp -s "$payload_path" "$target_path"
}

install_payload_script() {
  payload_name="$1"
  payload_path="$PAYLOAD_DIR/$payload_name"
  target_path="$HOST_SCRIPTS_DIR/$payload_name"

  if [ ! -f "$payload_path" ]; then
    return 0
  fi
  install -m 0755 "$payload_path" "$target_path" >/dev/null 2>&1
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
elif payload_differs "sender-backend" || payload_differs "sender-frontend" || payload_differs "setup-remote-tunnel"; then
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

if ! install_payload_script "sender-backend"; then
  release_lock
  log_warn "Failed to install sender-backend payload script."
  post_sync_failure_alert "backend-install-failed"
  exit 0
fi

if ! install_payload_script "sender-frontend"; then
  release_lock
  log_warn "Failed to install sender-frontend payload script."
  post_sync_failure_alert "frontend-install-failed"
  exit 0
fi

if ! install_payload_script "setup-remote-tunnel"; then
  release_lock
  log_warn "Failed to install setup-remote-tunnel payload script."
  post_sync_failure_alert "tunnel-setup-install-failed"
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
