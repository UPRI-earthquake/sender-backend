# Sender Remote Tunnel Runbook (Reverse SSH via Bastion)

This runbook covers remote access for deployed RShake devices using reverse SSH (`autossh`) and per-device bastion users.

## 1. Bastion setup and registry ownership

Bastion scripts are server-owned in commons:

- `earthquake-hub-deployment/earthquake-hub-commons/bastion/register-device.sh`
- `earthquake-hub-deployment/earthquake-hub-commons/bastion/revoke-device.sh`
- `earthquake-hub-deployment/earthquake-hub-commons/bastion/list-devices.sh`

Registry source of truth:

- `/etc/upri/rshake-tunnels/devices.csv`
- Columns: `device_id,bastion_user,remote_port,status,key_fingerprint,created_at,revoked_at`

## 2. Device setup modes

### Manual fallback mode

1. Run server-side register script and capture returned env snippet.
2. On device, install tunnel service:
   - `sudo sender-backend INSTALL_REMOTE_TUNNEL_SERVICE`
3. Write `/etc/upri/sender-remote-tunnel.env` manually with the returned values.
4. Ensure key + known_hosts files exist and are secure.
5. Start service:
   - `sudo systemctl restart sender-remote-tunnel.service`

### Automatic enrollment mode

1. Ensure backend enrollment API is enabled (`POST /device/tunnel/enroll`).
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
   - write pinned known_hosts data,
   - start tunnel.

### Automatic helper script (reduced manual setup)

Use helper script from the sender-backend repo on the device:

- `sudo sender-setup-remote-tunnel --enroll-token "<sensor token>" --enroll-endpoint "https://earthquake.science.upd.edu.ph/api/device/tunnel/enroll"`
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
2. SSH to bastion.
3. SSH to device through assigned reverse port:
   - `ssh -p <remote_port> myshake@127.0.0.1`
4. Elevate only when needed:
   - `sudo <command>`

## 5. Key rotation

1. Generate new keypair per device.
2. Re-run server-side `register-device.sh` for same `--device-id` with new public key.
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

- Host key mismatch:
  - update pinned key in `REMOTE_TUNNEL_KNOWN_HOSTS_PATH`.
- Private key permission error:
  - ensure key is `600`/`400` and owned by service user.
- Enrollment API failure:
  - check `REMOTE_TUNNEL_ENROLL_TOKEN` and endpoint reachability.
- Service running but no bastion listener:
  - verify outbound network and bastion `sshd` logs.
