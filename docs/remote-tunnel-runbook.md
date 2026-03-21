# Sender Remote Tunnel Runbook (SSH over WebSocket)

This runbook covers the sender-side/device-side workflow for remote access on deployed RShake devices using reverse SSH-over-WebSocket (`wstunnel`) and per-device remote port mappings.

Server-side bastion registry ownership, operator access policy, and bastion scripts now live in EarthquakeHub commons. Treat this document as the sender-side companion runbook and use the commons documentation/scripts as the source of truth for bastion administration.

## 1. Bastion setup and registry ownership

Bastion scripts are server-owned in commons:

- `earthquake-hub-deployment/earthquake-hub-commons/bastion/register-device.sh`
- `earthquake-hub-deployment/earthquake-hub-commons/bastion/revoke-device.sh`
- `earthquake-hub-deployment/earthquake-hub-commons/bastion/list-devices.sh`

Registry source of truth:

- `/etc/upri/rshake-tunnels/devices.csv`
- Columns: `device_id,bastion_user,remote_port,status,key_fingerprint,created_at,revoked_at`

This repo does not own those bastion assets. This repo owns the device-side tunnel service, enrollment flow, helper script, and health reporting.

## 2. Device setup modes

### Manual fallback mode

1. Run the server-side register script in commons and capture the returned env snippet.
2. On device, install tunnel service:
   - `sudo sender-backend INSTALL_REMOTE_TUNNEL_SERVICE`
3. Write `/etc/upri/sender-remote-tunnel.env` manually with the returned values.
4. Set the WebSocket transport settings:
   - `REMOTE_TUNNEL_WSS_URL=wss://earthquake.science.upd.edu.ph`
   - `REMOTE_TUNNEL_WSS_PATH_PREFIX=api/ws-tunnel/<secret>`
5. Start service:
   - `sudo systemctl restart sender-remote-tunnel.service`

### Automatic enrollment mode

1. Ensure the backend enrollment API is enabled in the deployed backend (`POST /device/tunnel/enroll`).
2. Configure device env file with:
   - `REMOTE_TUNNEL_AUTO_REGISTER_ENABLED=true`
   - `REMOTE_TUNNEL_ENROLL_TOKEN=<sensor bearer token>`
   - `REMOTE_TUNNEL_ENROLL_ENDPOINT=<optional override>`
3. Install/start tunnel service:
   - `sudo sender-backend INSTALL_REMOTE_TUNNEL_SERVICE`
4. On first start (if mapping fields are incomplete), sender will:
   - generate/load tunnel keypair,
   - call enrollment API,
   - write/update `/etc/upri/sender-remote-tunnel.env`,
   - persist received WebSocket settings (`REMOTE_TUNNEL_WSS_URL`, `REMOTE_TUNNEL_WSS_PATH_PREFIX`) when present,
   - start tunnel.

### Automatic helper script (reduced manual setup)

Use the helper script from this repo on the device:

- Ensure host packages are installed first:
  - `sudo apt-get update`
  - `sudo apt-get install -y openssh-client`
  - `wstunnel` auto-install is attempted from the pinned upstream GitHub release when missing
- `sudo sender-setup-remote-tunnel --enroll-token "<sensor token>" --enroll-endpoint "https://earthquake.science.upd.edu.ph/api/device/tunnel/enroll"`
  - optional overrides: `--wss-url ... --wss-path-prefix ...`
- If you are running from a checked-out repo instead of an installed wrapper, use:
  - `sudo ./setup-remote-tunnel.sh --enroll-token "<sensor token>" --enroll-endpoint "https://earthquake.science.upd.edu.ph/api/device/tunnel/enroll"`
- If `--enroll-token` is omitted, helper attempts to auto-discover an existing sender access token from tunnel env and sender token storage.

The helper will:

- write/update `/etc/upri/sender-remote-tunnel.env` with auto-register enabled
- install remote tunnel service if needed
- restart the service
- print `REMOTE_TUNNEL_STATUS` output

## 3. Verification

- `sender-backend REMOTE_TUNNEL_STATUS`
- `curl http://localhost:5001/health/sender-state` (check `payload.remoteTunnel`)

## 4. Operator access pattern

1. Connect to OpenVPN.
2. SSH to the commons-managed bastion.
3. SSH to device through assigned reverse port:
   - `ssh -p <remote_port> myshake@127.0.0.1`
4. Elevate only when needed:
   - `sudo <command>`

## 5. Key rotation

1. Generate new keypair per device.
2. Re-run the commons-side `register-device.sh` for the same `--device-id` with the new public key.
3. Replace private key on device (`REMOTE_TUNNEL_KEY_PATH`) if required.
4. Restart tunnel service.
5. Validate with `REMOTE_TUNNEL_STATUS` and operator SSH path.

## 6. Revocation and incident response

1. `sudo earthquake-hub-deployment/earthquake-hub-commons/bastion/revoke-device.sh --device-id <id>`
2. Confirm `list-devices.sh` shows `revoked`.
3. Stop tunnel service on device:
   - `sudo systemctl stop sender-remote-tunnel.service`
4. Rotate credentials before re-enable.

## 7. Common failure recovery

- Private key permission error:
  - ensure key is `600`/`400` and owned by service user.
- Enrollment API failure:
  - check `REMOTE_TUNNEL_ENROLL_TOKEN` and endpoint reachability.
- Service running but no remote listener:
  - verify outbound HTTPS reachability and `wstunnel` logs (`journalctl -u sender-remote-tunnel.service -n 100 --no-pager`).
