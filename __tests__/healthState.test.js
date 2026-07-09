const request = require('supertest');
const fs = require('fs').promises;
const os = require('os');
const path = require('path');

describe('GET /health/sender-state', () => {
  let app;
  let tempRoot;
  let tempLocalDbs;
  let tokenRefreshStatePath;
  let autoUpdateStatePath;
  let watchdogStatePath;
  let diskStatePath;
  let remoteTunnelStatePath;

  beforeAll(async () => {
    jest.resetModules();
    process.env.NODE_ENV = 'test';

    tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'sender-backend-health-state-'));
    tempLocalDbs = path.join(tempRoot, 'localDBs');
    await fs.mkdir(tempLocalDbs, { recursive: true });

    tokenRefreshStatePath = path.join(tempLocalDbs, 'token-refresh-alert-state.json');
    autoUpdateStatePath = path.join(tempRoot, 'update-state.json');
    watchdogStatePath = path.join(tempRoot, 'watchdog-state.env');
    diskStatePath = path.join(tempRoot, 'disk-alert-state.env');
    remoteTunnelStatePath = path.join(tempRoot, 'remote-tunnel-state.json');

    process.env.LOCALDBS_DIRECTORY = tempLocalDbs;
    process.env.TOKEN_REFRESH_ALERT_STATE_FILE = tokenRefreshStatePath;
    process.env.AUTO_UPDATE_STATE_FILE = autoUpdateStatePath;
    process.env.WATCHDOG_STATE_FILE = watchdogStatePath;
    process.env.DISK_ALERT_STATE_FILE = diskStatePath;
    process.env.REMOTE_TUNNEL_STATE_FILE = remoteTunnelStatePath;

    await fs.writeFile(tokenRefreshStatePath, JSON.stringify({
      failureCount: 1,
      failureActive: true,
      lastSuccessAlertAt: 0,
    }));
    await fs.writeFile(autoUpdateStatePath, JSON.stringify({
      timestamp: '2026-03-07T00:00:00Z',
      bundleTag: 'latest',
      backendResult: 'updated',
      frontendResult: 'updated',
      alertPostResult: 'failed-http-403',
      alertHttpStatus: '403',
      alertPostError: 'HTTP 403: invalid shared secret',
      tunnelEnrollment: {
        result: 'partial',
        service: 'active-disconnected',
        nextStep: 'check-remote-tunnel-service',
      },
    }));
    await fs.writeFile(watchdogStatePath, 'WATCHDOG_BACKEND_LAST_RESTART_TS=123\nWATCHDOG_FRONTEND_LAST_RESTART_TS=456\n');
    await fs.writeFile(diskStatePath, 'LAST_DISK_ALERT_LEVEL=warn\nLAST_DISK_ALERT_FREE_PCT=11\n');
    await fs.writeFile(remoteTunnelStatePath, JSON.stringify({
      connected: true,
      lastConnectedAt: '2026-03-09T01:00:00Z',
      lastError: null,
      deviceId: 'AM-R24FA',
      bastionHost: 'ops.example.org',
      bastionPort: 443,
      remotePort: 22501,
    }));

    app = require('../src/app');
  });

  afterAll(async () => {
    if (tempRoot) {
      await fs.rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('responds with a sender state snapshot', async () => {
    const response = await request(app).get('/health/sender-state');
    expect(response.statusCode).toBe(200);
    expect(response.body?.payload?.tokenRefreshAlerts?.available).toBe(true);
    expect(response.body?.payload?.autoUpdate?.available).toBe(true);
    expect(response.body?.payload?.watchdog?.available).toBe(true);
    expect(response.body?.payload?.diskAlerts?.available).toBe(true);
    expect(response.body?.payload?.remoteTunnel?.available).toBe(true);
  });

  it('returns parsed values from state files', async () => {
    const response = await request(app).get('/health/sender-state');
    expect(response.body?.payload?.tokenRefreshAlerts?.state?.failureCount).toBe(1);
    expect(response.body?.payload?.autoUpdate?.state?.backendResult).toBe('updated');
    expect(response.body?.payload?.autoUpdate?.state?.alertHttpStatus).toBe('403');
    expect(response.body?.payload?.autoUpdate?.state?.tunnelEnrollment?.service).toBe('active-disconnected');
    expect(response.body?.payload?.watchdog?.state?.WATCHDOG_BACKEND_LAST_RESTART_TS).toBe(123);
    expect(response.body?.payload?.diskAlerts?.state?.LAST_DISK_ALERT_LEVEL).toBe('warn');
    expect(response.body?.payload?.remoteTunnel?.state?.deviceId).toBe('AM-R24FA');
    expect(response.body?.payload?.remoteTunnel?.state?.connected).toBe(true);
  });

  it('returns remoteTunnel unavailable when state file is missing', async () => {
    await fs.rm(remoteTunnelStatePath, { force: true });
    const response = await request(app).get('/health/sender-state');
    expect(response.statusCode).toBe(200);
    expect(response.body?.payload?.remoteTunnel?.available).toBe(false);
  });

  it('returns remoteTunnel unavailable when state file is malformed', async () => {
    await fs.writeFile(remoteTunnelStatePath, '{invalid-json');
    const response = await request(app).get('/health/sender-state');
    expect(response.statusCode).toBe(200);
    expect(response.body?.payload?.remoteTunnel?.available).toBe(false);
  });
});
