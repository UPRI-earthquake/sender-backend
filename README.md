# Sender-backend
Sender-backend program is the server-side component of the sender web application running on the Raspberry Shake device. For more details, you may refer to the [repository overview and API](https://upri-earthquake.github.io).  

## Installation on a [RaspberryShake Device](https://shop.raspberryshake.org/)
To install the entire sender software package, run the following command on the [RaspberryShake terminal](https://manual.raspberryshake.org/ssh.html):
```bash
bash <(curl "https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/rshake-alerts/install.sh")
```

### Optional: pre-install health check
Before installing, you can verify connectivity, disk space, OS/arch, and time sync:
```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/rshake-alerts/preinstall-health-check.sh")
```
If everything passes, proceed with the installer command above. Results are printed directly to the terminal.

### Auto-Update v2 Layout
Current sender rollout keeps stable launchers in `/usr/local/bin` and stores mutable script payloads in `/opt/upri/host-scripts`:
- `/usr/local/bin/sender-backend` -> wrapper that delegates to `/opt/upri/host-scripts/sender-backend`
- `/usr/local/bin/sender-frontend` -> wrapper that delegates to `/opt/upri/host-scripts/sender-frontend`

The backend container mounts `/opt/upri/host-scripts` and runs a startup sync hook to self-heal payload scripts from the image bundle when needed.

For existing deployments using older launchers, run one-time bootstrap:
```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/rshake-alerts/update.sh")
```
After bootstrap, normal operator commands stay the same (`sender-backend START`, etc.).

## Development Setup
To run this repository on your local machine, please follow the instructions provided under the [Setting Up The Repository On Your Local Machine](CONTRIBUTING.md#setting-up-the-repository-on-your-local-machine) section of the [contributing.md](CONTRIBUTING.md).

### Local dev stacks (Docker)

#### Option A: self-contained (sender-backend + local W1 + local MongoDB)
Use `docker-compose.yml` in this repo.

```bash
cp .env.example .env
docker compose --env-file .env up --build
```

#### Option B: commons-backed (sender-backend + optional sender-frontend)
Use `docker-compose.dev.yml` in this repo. This stack assumes the EarthquakeHub “commons” stack is already running and has created the external Docker network `earthquake-hub-network`.

1. Start the commons stack from `earthquake-hub-deployment/earthquake-hub-commons` (so that `ehub-backend` is available on `earthquake-hub-network`).
2. Prepare the env file (defaults are for Option A, so update W1 targets for commons):
   ```bash
   cp .env.example .env
   # edit .env as needed; for commons use:
   #   W1_DEV_IP=ehub-backend
   #   W1_DEV_PORT=5000
   ```
3. Start the backend (talking to commons):
   ```bash
   docker compose --env-file .env -f docker-compose.dev.yml up --build
   ```
   Optional: if you also have the `sender-frontend` repo cloned next to this repo at `../sender-frontend`, start it too:
   ```bash
   docker compose --env-file .env -f docker-compose.dev.yml --profile frontend up --build
   ```

Backend: `http://localhost:5001` (and frontend, if enabled: `http://localhost:3000`).

To sanity-check the backend once containers are up:
```bash
curl http://localhost:5001/health/time
curl http://localhost:5001/health/resources
curl http://localhost:5001/health/sender-state
curl http://localhost:5001/health/metrics
curl http://localhost:5001/device/info
```

### Update Bundle Controls
Host update scripts resolve tags to digests before deployment:
- `SENDER_BUNDLE_TAG` (default `latest`; can be pinned to semver like `1.2.2`)
- `SENDER_BACKEND_IMAGE_REPO` (default `ghcr.io/upri-earthquake/sender-backend`)
- `SENDER_FRONTEND_IMAGE_REPO` (default `ghcr.io/upri-earthquake/sender-frontend`)
- `AUTO_UPDATE_ROLLBACK_ENABLED` (default `true`; attempts rollback to previous running digests when an update run fails)

State snapshots are written to `/var/lib/upri-sender/update-state.json` (fallback to `/tmp/upri-sender/update-state.json` if permissions prevent writing to `/var/lib`).

### Sender Infrastructure Alerts
Sender posts admin-only RShake alerts for:
- Disk monitor (runs with daily `UPDATE_STACK` timer): `DISK_SPACE_WARN`, `DISK_SPACE_CRITICAL`, `DISK_SPACE_RECOVERY`
- Proactive token refresh scheduler: `TOKEN_REFRESH_FAILED`, `TOKEN_REFRESH_RECOVERY`, `TOKEN_REFRESH_SUCCESS`
- Stack watchdog timer: `WATCHDOG_CONTAINER_RESTARTED`, `WATCHDOG_CONTAINER_RESTART_FAILED`

Useful env controls:
- `DISK_ALERT_PATHS`, `DISK_ALERT_WARN_FREE_PCT`, `DISK_ALERT_CRITICAL_FREE_PCT`, `DISK_ALERT_RECOVERY_FREE_PCT`
- `TOKEN_REFRESH_FAILED_CONSECUTIVE_THRESHOLD`, `TOKEN_REFRESH_SUCCESS_COOLDOWN_SEC`
- `WATCHDOG_ENABLED`, `WATCHDOG_INTERVAL_MINUTES`, `WATCHDOG_BACKEND_STOPPED_MAX_SEC`, `WATCHDOG_FRONTEND_STOPPED_MAX_SEC`
- Alert post resilience/cooldown: `RSHAKE_ALERT_RETRY_ATTEMPTS`, `RSHAKE_ALERT_RETRY_BASE_MS`, `RSHAKE_ALERT_MIN_INTERVAL_SEC`
- Optional local alert queue: `RSHAKE_ALERT_QUEUE_ENABLED`, `RSHAKE_ALERT_QUEUE_FILE`, `RSHAKE_ALERT_QUEUE_MAX_SIZE`, `RSHAKE_ALERT_QUEUE_MAX_ATTEMPTS`

All of the above include `details.notificationScope=admin-only` and are posted to `W1_RS_ALERT_PATH` (default `/messaging/restricted/rshake-alert`).

### Sender State Snapshot Endpoint
`/health/sender-state` returns a read-only snapshot of sender operational state files when present:
- token refresh alert state
- auto-update state
- watchdog state
- disk-alert state

This helps debugging in the field without SSHing into the device for every check.

### Metrics Endpoint
`/health/metrics` exports in-process sender metrics plus rolling health trend history:
- HTTP request counters/latency summary by path
- alert post outcome counters (`success`, `error`, `queued`, etc.)
- health check trend history (`network`, `time`, `resources`, `senderState`)

Useful controls:
- `METRICS_PERSIST_HEALTH_HISTORY`
- `METRICS_HEALTH_HISTORY_FILE`
- `METRICS_HEALTH_HISTORY_LIMIT`
- `METRICS_HEALTH_HISTORY_FLUSH_MS`
- `SENDER_STRUCTURED_LOGS` (`true` emits JSON request logs to stdout)

### Stack Watchdog
`sender-backend INSTALL_SERVICE` now installs two timers:
- Daily updater timer (`sender-backend-update.timer`)
- Periodic watchdog timer (`sender-stack-watchdog.timer`)

The watchdog checks backend/frontend container runtime state and attempts start/restart after configured inactivity thresholds. It also enforces Docker restart policy `unless-stopped` on both containers.

### Remote Tunnel (Reverse SSH)
`sender-backend INSTALL_SERVICE` also installs and enables:
- `sender-remote-tunnel.service` (always-on reverse SSH tunnel via `autossh`)

`install.sh` provisions the service, but tunnel enrollment/config still depends on `/etc/upri/sender-remote-tunnel.env`.

Remote tunnel service commands:
- `sender-backend INSTALL_REMOTE_TUNNEL_SERVICE`
- `sender-backend UNINSTALL_REMOTE_TUNNEL_SERVICE`
- `sender-backend REMOTE_TUNNEL_START`
- `sender-backend REMOTE_TUNNEL_STOP`
- `sender-backend REMOTE_TUNNEL_STATUS`

Automatic setup helper (recommended to reduce manual steps on deployed devices):
- `setup-remote-tunnel.sh`
- `sender-setup-remote-tunnel` (installed by `install.sh`)
- Example:
  - `sudo sender-setup-remote-tunnel --enroll-token "<sensor token>" --enroll-endpoint "https://earthquake.science.upd.edu.ph/api/device/tunnel/enroll"`
- If `--enroll-token` is omitted, the helper attempts to auto-discover an existing sender access token from current tunnel env and sender token storage.
- The helper writes `/etc/upri/sender-remote-tunnel.env`, runs `sender-backend INSTALL_REMOTE_TUNNEL_SERVICE`, restarts `sender-remote-tunnel.service`, and prints tunnel status.

Device tunnel env file:
- `/etc/upri/sender-remote-tunnel.env`
- Generated template is created automatically on service install (defaults to `REMOTE_TUNNEL_ENABLED=false`).

Supported tunnel env vars:
- `REMOTE_TUNNEL_ENABLED`
- `REMOTE_TUNNEL_DEVICE_ID`
- `REMOTE_TUNNEL_BASTION_HOST`
- `REMOTE_TUNNEL_BASTION_PORT`
- `REMOTE_TUNNEL_BASTION_USER`
- `REMOTE_TUNNEL_REMOTE_PORT`
- `REMOTE_TUNNEL_LOCAL_HOST`
- `REMOTE_TUNNEL_LOCAL_PORT`
- `REMOTE_TUNNEL_KEY_PATH`
- `REMOTE_TUNNEL_KNOWN_HOSTS_PATH`
- `REMOTE_TUNNEL_SERVER_ALIVE_INTERVAL`
- `REMOTE_TUNNEL_SERVER_ALIVE_COUNT_MAX`
- `REMOTE_TUNNEL_CONNECT_TIMEOUT_SEC`
- `REMOTE_TUNNEL_STATE_FILE`
- `REMOTE_TUNNEL_PID_FILE`
- `REMOTE_TUNNEL_AUTO_REGISTER_ENABLED` (default `false`)
- `REMOTE_TUNNEL_ENROLL_ENDPOINT` (defaults to `<W1 base>/device/tunnel/enroll` when derivable)
- `REMOTE_TUNNEL_ENROLL_TOKEN` (sensor bearer token for enrollment API)
- `REMOTE_TUNNEL_ENROLL_REQUEST_TIMEOUT_SEC`
- `REMOTE_TUNNEL_BASTION_HOST_KEY` (optional known_hosts pin line)

`/health/sender-state` now also reports `remoteTunnel` when the state file is available.

Bastion automation scripts are now server-owned under commons:
- `earthquake-hub-deployment/earthquake-hub-commons/bastion/register-device.sh`
- `earthquake-hub-deployment/earthquake-hub-commons/bastion/revoke-device.sh`
- `earthquake-hub-deployment/earthquake-hub-commons/bastion/list-devices.sh`

Runbook:
- `docs/remote-tunnel-runbook.md`

### RShake settings fixtures for dev
- `dev/settings` mirrors the `/opt/settings` layout of an RShake (including `sys` files plus `config/config.json` and `config/MD-info.json` from the screenshots). The compose file mounts this tree to `/opt/settings`, matching the default `RSHAKE_SETTINGS_PATH`.
- Update those fixtures if you need to test different coordinates or station IDs; the backend will read from `config.json`/`MD-info.json` first and fall back to `sys` text files and `station.xml`.
- When running the backend directly on your host, point `RSHAKE_SETTINGS_PATH` at `./dev/settings` so the same fixtures are used outside Docker.

If you prefer running the backend directly on your host instead of inside Docker, set `SLINK2DALIPATH` to a locally built binary (e.g., `./tests2d/slink2dali` after `make`) and `LOCALDBS_DIRECTORY` to a writable path such as `./localDBs`.

### Clock health target
The `/health/time` endpoint now issues an SNTP query instead of relying on HTTP `Date` headers and will walk a list of hosts until one responds. Configure the target via:

| Variable | Default | Description |
| --- | --- | --- |
| `NTP_SERVER_HOST` | `time.google.com` | Primary host queried for time offset. |
| `NTP_SERVER_HOSTS` | _(empty)_ | Optional comma/space separated fallback hosts (e.g. `time.google.com,0.asia.pool.ntp.org`). Entries can include `host:port`. |
| `NTP_SERVER_PORT` | `123` | UDP port for the SNTP request. |
| `NTP_REQUEST_TIMEOUT_MS` | `2000` | Milliseconds before the query aborts. |

Set these in `.env` (or your container environment) if you need to point at a regional NTP source.

### Network health TLS verification
`/health/network` verifies HTTPS certificates by default. If you intentionally need to probe a self-signed endpoint, set:

| Variable | Default | Description |
| --- | --- | --- |
| `HEALTH_ALLOW_INSECURE_TLS` | `false` | When `true`, `/health/network` skips TLS certificate verification for its HTTPS probe. Use only for troubleshooting. |

### W1 TLS verification policy
W1 API calls currently preserve legacy behavior (insecure TLS allowed). To enforce certificate verification on production W1 calls, set:

| Variable | Default | Description |
| --- | --- | --- |
| `W1_ALLOW_INSECURE_TLS` | `true` | When `false`, backend enforces TLS certificate verification for W1 calls (`/device/link`, refresh, unlink, reset-link). |
