#!/bin/sh
# Pre-install health check for sender/telemetry nodes (Raspberry Pi / Shake, etc).
# Run this before invoking the installer to catch common field issues.

# --- Configurable defaults (override via environment variables) ----------------
PING_HOSTS="${PING_HOSTS:-1.1.1.1 8.8.8.8}"
HTTP_URLS="${HTTP_URLS:-https://github.com https://google.com}"
DNS_HOSTNAMES="${DNS_HOSTNAMES:-github.com pool.ntp.org}"
DNS_RESOLV_PATH="${DNS_RESOLV_PATH:-/etc/resolv.conf}"
NTP_SERVER="${NTP_SERVER:-pool.ntp.org}"
TIME_HTTP_CHECK_URL="${TIME_HTTP_CHECK_URL:-https://google.com}"
DISK_PATH="${DISK_PATH:-/}"
MIN_FREE_DISK_MB="${MIN_FREE_DISK_MB:-512}"
WRITABLE_TEST_DIR="${WRITABLE_TEST_DIR:-/tmp}"
ACCEPT_ARCHS="${ACCEPT_ARCHS:-armv7l aarch64 x86_64}"
ACCEPT_OS_IDS="${ACCEPT_OS_IDS:-raspbian debian ubuntu}"
ACCEPT_OS_CODENAMES="${ACCEPT_OS_CODENAMES:-buster bullseye bookworm focal jammy}"
PING_ATTEMPTS="${PING_ATTEMPTS:-2}"
PING_TIMEOUT="${PING_TIMEOUT:-3}"
RESOLVE_RETRIES="${RESOLVE_RETRIES:-2}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"
MAX_TIME_SKEW_SEC="${MAX_TIME_SKEW_SEC:-120}"
NTP_TIMEOUT="${NTP_TIMEOUT:-5}"
NTP_CONF_PATH="${NTP_CONF_PATH:-/etc/ntp.conf}"
NTP_POOL_ENTRY="${NTP_POOL_ENTRY:-server 0.asia.pool.ntp.org}"
NTP_AUTO_REPAIR="${NTP_AUTO_REPAIR:-0}"
NTP_SERVICE_NAME="${NTP_SERVICE_NAME:-ntp}"

CRITICAL_FAIL=0
WARNINGS=0

if [ -t 1 ] && [ "${NO_COLOR:-0}" = "0" ]; then
  ESC="$(printf '\033')"
  COLOR_PASS="${ESC}[32m"
  COLOR_WARN="${ESC}[33m"
  COLOR_FAIL="${ESC}[31m"
  COLOR_RESET="${ESC}[0m"
else
  COLOR_PASS=""
  COLOR_WARN=""
  COLOR_FAIL=""
  COLOR_RESET=""
fi

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

status_pass() { log "${COLOR_PASS}[PASS]${COLOR_RESET} $*"; }
status_warn() { WARNINGS=1; log "${COLOR_WARN}[WARN]${COLOR_RESET} $*"; }
status_fail() { CRITICAL_FAIL=1; log "${COLOR_FAIL}[FAIL]${COLOR_RESET} $*"; }

with_timeout() {
  t="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$t" "$@"
  else
    "$@"
  fi
}

word_in_list() {
  needle="$1"
  shift
  for item in "$@"; do
    [ "$needle" = "$item" ] && return 0
  done
  return 1
}

get_resolvers() {
  if [ -f "$DNS_RESOLV_PATH" ]; then
    awk '/^nameserver[[:space:]]+/ {print $2}' "$DNS_RESOLV_PATH" | tr '\n' ' ' | awk '{$1=$1;print}'
  else
    echo ""
  fi
}

resolve_host() {
  target="$1"
  i=0
  while [ "$i" -le "$RESOLVE_RETRIES" ]; do
    if command -v host >/dev/null 2>&1; then
      addr=$(host "$target" 2>/dev/null | awk '/has address/ {print $4; exit}')
    elif command -v dig >/dev/null 2>&1; then
      addr=$(dig +short "$target" A 2>/dev/null | head -n1)
    elif command -v getent >/dev/null 2>&1; then
      addr=$(getent hosts "$target" 2>/dev/null | awk '{print $1; exit}')
    else
      return 2
    fi

    [ -n "$addr" ] && { echo "$addr"; return 0; }
    i=$((i + 1))
    sleep 1
  done
  return 1
}

# --- Checks -------------------------------------------------------------------

check_interfaces() {
  if ! command -v ip >/dev/null 2>&1; then
    status_fail "'ip' command not found; cannot inspect interfaces.
  Actions: install iproute2 or run on a device with ip; manually check link status with ifconfig."
    return
  fi

  ips=$(ip -4 -o addr show scope global up | awk '{print $2" "$4}')
  if [ -z "$ips" ]; then
    status_fail "No active interface with an IPv4 address (DHCP/static config issue?).
  Actions: run 'ip addr' to confirm link, 'ip link set <iface> up', renew DHCP with 'sudo dhclient -v <iface>' or verify static config."
    return
  fi

  status_pass "Active IPv4 addresses: $(echo "$ips" | tr '\n' '; ')"
}

check_dns() {
  missing_tools=0
  failures=0
  resolvers="$(get_resolvers)"
  if [ -n "$resolvers" ]; then
    dns_example="$resolvers"
  else
    dns_example="<resolver-ip>"
  fi

  for host in $DNS_HOSTNAMES; do
    resolved=$(resolve_host "$host")
    case $? in
      0) log "Resolved $host -> $resolved" ;;
      1) failures=$((failures + 1)); log "Could not resolve $host after retries" ;;
      2) missing_tools=1 ;;
    esac
  done

  if [ "$missing_tools" -eq 1 ]; then
    status_warn "No DNS lookup tools available (install dnsutils or use getent); skipping resolution test"
    return
  fi

  if [ "$failures" -eq 0 ]; then
    status_pass "DNS resolution ok for: $DNS_HOSTNAMES"
  else
    status_fail "DNS resolution failed for $failures hostname(s).
  Actions: inspect /etc/resolv.conf, test 'getent hosts <hostname>', restart DHCP with 'sudo dhclient -v <iface>', or set a known-good resolver.
  Note: If DNS works on the host but containers fail, override sender-backend DNS.
  Example: sudo SENDER_BACKEND_DNS=\"$dns_example\" sender-backend UPDATE"
  fi
}

check_outbound() {
  ping_ok=0
  resolvers="$(get_resolvers)"
  if [ -n "$resolvers" ]; then
    dns_example="$resolvers"
  else
    dns_example="<resolver-ip>"
  fi

  for host in $PING_HOSTS; do
    attempt=1
    while [ "$attempt" -le "$PING_ATTEMPTS" ]; do
      if with_timeout "$PING_TIMEOUT" ping -c1 -W "$PING_TIMEOUT" "$host" >/dev/null 2>&1; then
        ping_ok=1
        log "Ping reachable: $host (attempt $attempt)"
        break 2
      fi
      attempt=$((attempt + 1))
      sleep 1
    done
  done
  if [ "$ping_ok" -eq 1 ]; then
    status_pass "ICMP reachability looks good (sample host reachable)"
  else
    status_fail "No ICMP reachability to any of: $PING_HOSTS (check uplink, firewall, or gateway).
  Actions: run 'ip route' to find the default gateway, then 'ping -c3 <gateway>'; verify cable/Wi-Fi and upstream firewall rules."
  fi

  http_tool=""
  if command -v curl >/dev/null 2>&1; then
    http_tool="curl"
  elif command -v wget >/dev/null 2>&1; then
    http_tool="wget"
  fi

  if [ -z "$http_tool" ]; then
    status_warn "Neither curl nor wget found; cannot test HTTP/HTTPS egress"
    return
  fi

  http_ok=0
  for url in $HTTP_URLS; do
    if [ "$http_tool" = "curl" ]; then
      if with_timeout "$HTTP_TIMEOUT" curl -fsIL --max-time "$HTTP_TIMEOUT" "$url" >/dev/null 2>&1; then
        http_ok=1
        log "HTTP reachable: $url"
        break
      fi
    else
      if with_timeout "$HTTP_TIMEOUT" wget --spider --quiet --timeout="$HTTP_TIMEOUT" "$url" >/dev/null 2>&1; then
        http_ok=1
        log "HTTP reachable: $url"
        break
      fi
    fi
  done

  if [ "$http_ok" -eq 1 ]; then
    status_pass "HTTP/HTTPS reachability looks good (sample endpoint reachable)"
  else
    status_fail "HTTP/HTTPS reachability failed for: $HTTP_URLS (proxy/captive portal/firewall?).
  Actions: try 'curl -v --max-time $HTTP_TIMEOUT <url>', check for captive portal, and ensure outbound 80/443 is allowed.
  Note: If HTTPS works on the host but fails in containers, override sender-backend DNS using host resolvers.
  Example: sudo SENDER_BACKEND_DNS=\"$dns_example\" sender-backend UPDATE"
  fi
}

check_disk_space() {
  free_mb=$(df -Pm "$DISK_PATH" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -z "$free_mb" ]; then
    status_warn "Could not read disk usage for $DISK_PATH"
    return
  fi

  if [ "$free_mb" -lt "$MIN_FREE_DISK_MB" ]; then
    status_fail "Only ${free_mb}MB free on $DISK_PATH (need >= ${MIN_FREE_DISK_MB}MB).
  Actions: run 'df -h $DISK_PATH'; clean logs with 'sudo du -sh /var/log/* /var/tmp/*' and remove unused files."
  else
    status_pass "Disk space ok on $DISK_PATH: ${free_mb}MB free (min ${MIN_FREE_DISK_MB}MB)"
  fi
}

check_filesystem_writable() {
  tmpfile=$(mktemp "$WRITABLE_TEST_DIR/.preinstall-check.XXXX" 2>/dev/null)
  if [ -z "$tmpfile" ]; then
    status_fail "Cannot write under $WRITABLE_TEST_DIR (filesystem may be read-only).
  Actions: check mounts with 'mount | head', look for read-only flags, and inspect dmesg for I/O errors."
    return
  fi

  echo "test" >"$tmpfile" 2>/dev/null
  if [ $? -ne 0 ]; then
    rm -f "$tmpfile" 2>/dev/null
    status_fail "Write test failed in $WRITABLE_TEST_DIR (filesystem may be read-only).
  Actions: confirm media health, remount read-write if appropriate, or replace the SD card."
    return
  fi

  rm -f "$tmpfile" 2>/dev/null
  status_pass "Filesystem writable: $WRITABLE_TEST_DIR"
}

check_os_arch() {
  arch=$(uname -m 2>/dev/null || echo unknown)
  arch_ok=0
  for a in $ACCEPT_ARCHS; do
    [ "$arch" = "$a" ] && arch_ok=1 && break
  done

  os_id=""
  os_code=""
  if [ -r /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    os_id=$(printf '%s' "${ID:-}" | tr '[:upper:]' '[:lower:]')
    os_code=$(printf '%s' "${VERSION_CODENAME:-}" | tr '[:upper:]' '[:lower:]')
    if [ -z "$os_code" ] && [ -n "${VERSION:-}" ]; then
      os_code=$(printf '%s\n' "$VERSION" | sed -n 's/.*(//; s/).*//;p' | tr '[:upper:]' '[:lower:]')
    fi
  elif command -v lsb_release >/dev/null 2>&1; then
    os_id=$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')
    os_code=$(lsb_release -cs 2>/dev/null | tr '[:upper:]' '[:lower:]')
  fi

  os_ok=0
  if [ -n "$os_id" ] && [ -n "$os_code" ]; then
    if word_in_list "$os_id" $ACCEPT_OS_IDS && word_in_list "$os_code" $ACCEPT_OS_CODENAMES; then
      os_ok=1
    fi
  fi

  if [ "$arch_ok" -eq 1 ] && [ "$os_ok" -eq 1 ]; then
    status_pass "Platform ok: $arch on $os_id $os_code"
    return
  fi

  if [ "$arch_ok" -ne 1 ]; then
    status_fail "Unsupported CPU arch: $arch (allowed: $ACCEPT_ARCHS).
  Actions: run 'uname -m' to confirm; use a supported Raspberry Pi/Raspbian image."
  fi
  if [ -z "$os_id" ]; then
    status_warn "Could not determine OS version (/etc/os-release missing); verify manually.
  Actions: check 'cat /etc/os-release' and 'lsb_release -a' if available."
  elif [ "$os_ok" -ne 1 ]; then
    status_fail "Unsupported OS/codename: $os_id $os_code (allowed IDs: $ACCEPT_OS_IDS; codenames: $ACCEPT_OS_CODENAMES).
  Actions: verify with 'cat /etc/os-release'; reinstall with a supported Raspbian/Debian release."
  fi
}

check_time_sync() {
  checked=0

  if command -v curl >/dev/null 2>&1; then
    header=$(with_timeout "$HTTP_TIMEOUT" curl -Is "$TIME_HTTP_CHECK_URL" 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /^Date:/ {sub(/^Date:[[:space:]]*/, ""); print; exit}')
    if [ -n "$header" ]; then
      remote_epoch=$(date -d "$header" +%s 2>/dev/null)
      local_epoch=$(date +%s)
      if [ -n "$remote_epoch" ] && [ -n "$local_epoch" ]; then
        diff=$((local_epoch - remote_epoch))
        abs=${diff#-}
        if [ "$abs" -le "$MAX_TIME_SKEW_SEC" ]; then
          status_pass "Clock offset $abs s vs HTTP Date from $TIME_HTTP_CHECK_URL (max ${MAX_TIME_SKEW_SEC}s)"
        else
          status_fail "Clock offset $abs s vs $TIME_HTTP_CHECK_URL (NTP/time sync misconfigured).
  Actions: check 'timedatectl status' if available, or run 'sudo ntpdate -qu $NTP_SERVER' to resync."
        fi
        checked=1
      fi
    fi
  fi

  if [ "$checked" -eq 0 ] && command -v ntpdate >/dev/null 2>&1; then
    if with_timeout "$NTP_TIMEOUT" ntpdate -qu "$NTP_SERVER" >/dev/null 2>&1; then
      status_pass "NTP server reachable: $NTP_SERVER (ntpdate query succeeded)"
    else
      status_warn "Unable to query NTP server $NTP_SERVER with ntpdate; ensure time sync is configured"
    fi
    checked=1
  fi

  if [ "$checked" -eq 0 ] && command -v chronyc >/dev/null 2>&1; then
    if with_timeout "$NTP_TIMEOUT" chronyc tracking >/dev/null 2>&1; then
      status_pass "chrony responds; time sync likely configured (check chronyc tracking for details)"
    else
      status_warn "chronyc tracking failed; time sync may be misconfigured"
    fi
    checked=1
  fi

  if [ "$checked" -eq 0 ]; then
    status_warn "Could not verify time sync (missing curl/ntpdate/chronyc); check clock manually"
  fi
}

check_ntp_runtime() {
  if command -v timedatectl >/dev/null 2>&1; then
    status_output=$(timedatectl status 2>/dev/null)
    synced=$(echo "$status_output" | awk -F': ' '/System clock synchronized/ {print tolower($2); exit}')
    service=$(echo "$status_output" | awk -F': ' '/NTP service/ {print tolower($2); exit}')
    combined="timedatectl: System clock synchronized=${synced:-unknown}; NTP service=${service:-unknown}"
    if [ "$synced" = "yes" ] || [ "$service" = "active" ]; then
      status_pass "$combined"
    else
      status_warn "$combined.
  Actions: run 'sudo timedatectl set-ntp true' or install/start ntp/chrony so the clock can sync."
    fi
    return
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet "$NTP_SERVICE_NAME" 2>/dev/null; then
      status_pass "systemctl: $NTP_SERVICE_NAME service is active."
    else
      status_warn "systemctl: $NTP_SERVICE_NAME service is inactive or missing.
  Actions: install and start it via 'sudo apt install ntp && sudo systemctl enable --now $NTP_SERVICE_NAME', or configure chrony/timesyncd."
    fi
    return
  fi

  status_warn "Unable to read NTP service status (timedatectl/systemctl unavailable); verify manually with 'ps -ef | grep ntp'."
}

check_ntp_configuration() {
  if [ ! -f "$NTP_CONF_PATH" ]; then
    status_warn "NTP config $NTP_CONF_PATH not found (install ntp or set NTP_CONF_PATH)."
    return
  fi

  desired_host=$(printf '%s\n' "$NTP_POOL_ENTRY" | awk '{print $2}')
  display_host="$desired_host"
  [ -z "$display_host" ] && display_host="$NTP_POOL_ENTRY"
  entry_present=0

  if [ -n "$desired_host" ]; then
    if grep -Eq "^[[:space:]]*(server|pool)[[:space:]]+$desired_host([[:space:]]|$)" "$NTP_CONF_PATH"; then
      entry_present=1
    fi
  else
    if grep -Fq "$NTP_POOL_ENTRY" "$NTP_CONF_PATH"; then
      entry_present=1
    fi
  fi

  if [ "$entry_present" -eq 1 ]; then
    status_pass "$NTP_CONF_PATH already contains $display_host."
    return
  fi

  if [ "$NTP_AUTO_REPAIR" -eq 1 ]; then
    if [ ! -w "$NTP_CONF_PATH" ]; then
      status_fail "Cannot modify $NTP_CONF_PATH (insufficient permissions). Run with sudo or set NTP_AUTO_REPAIR=0 to skip auto-fix."
      return
    fi
    backup="${NTP_CONF_PATH}.preinstall.$(date +%Y%m%d%H%M%S).bak"
    if cp "$NTP_CONF_PATH" "$backup" 2>/dev/null; then
      if printf '\n%s\n' "$NTP_POOL_ENTRY" >> "$NTP_CONF_PATH"; then
        status_pass "Appended '$NTP_POOL_ENTRY' to $NTP_CONF_PATH (backup at $backup)."
      else
        status_fail "Failed to append '$NTP_POOL_ENTRY' to $NTP_CONF_PATH (backup at $backup)."
      fi
    else
      status_fail "Unable to back up $NTP_CONF_PATH to $backup; aborting auto-repair."
    fi
  else
    status_warn "$NTP_CONF_PATH is missing '$NTP_POOL_ENTRY'.
  Actions: run 'sudo nano $NTP_CONF_PATH' and add the line before other Debian pool entries (see https://upri-earthquake.github.io/issues/rshake-ntp-issue.html), or rerun with NTP_AUTO_REPAIR=1 to append automatically."
  fi
}

# --- Main ---------------------------------------------------------------------
main() {
  log "=== Starting sender pre-install health check ==="

  check_interfaces
  check_dns
  check_outbound
  check_disk_space
  check_filesystem_writable
  check_os_arch
  check_time_sync
  check_ntp_runtime
  check_ntp_configuration

  log "=== Summary ==="
  if [ "$CRITICAL_FAIL" -ne 0 ]; then
    log "One or more critical checks FAILED. Fix the issues above, then re-run this script."
    echo "Critical failures detected. Review the messages above."
    exit 1
  fi

  if [ "$WARNINGS" -ne 0 ]; then
    log "Completed with warnings. Review before proceeding."
    echo "Checks completed with warnings. Review the output above before installing."
  else
    log "All critical checks passed."
    echo "Environment looks healthy; it is safe to run the sender install script now."
  fi

  # Optional: automatically run the installer on success
  # ./preinstall-health-check.sh && bash <(curl -fsSL https://raw.githubusercontent.com/.../install.sh)
}

main "$@"
