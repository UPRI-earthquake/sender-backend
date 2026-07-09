const axios = require('axios');
const fs = require('fs');
const os = require('os');
const path = require('path');

jest.mock('axios', () => ({
  post: jest.fn(),
}));

jest.mock('../src/services/device.service', () => ({
  buildW1BaseUrl: jest.fn(),
  getStoredDeviceInfo: jest.fn(),
  syncRshakeAlertCredential: jest.fn(),
}));

jest.mock('../src/services/utils', () => ({
  getHostDeviceConfig: jest.fn(),
  read_mac_address: jest.fn(),
}));

jest.mock('../src/services/alertCredential.service', () => ({
  getStoredAlertSharedSecret: jest.fn(),
}));

const deviceService = require('../src/services/device.service');
const utils = require('../src/services/utils');
const alertCredentialService = require('../src/services/alertCredential.service');
const { postRshakeAlert } = require('../src/services/rshakeAlerts.service');

describe('rshakeAlerts.service', () => {
  const originalEnv = process.env;
  let tempDir;

  beforeEach(() => {
    jest.clearAllMocks();
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sender-rshake-alerts-'));
    process.env = { ...originalEnv };
    delete process.env.RSHAKE_ALERTS_ENABLED;
    delete process.env.W1_RS_ALERT_PATH;
    delete process.env.RSHAKE_ALERT_POST_TIMEOUT_MS;
    delete process.env.RSHAKE_ALERT_SCHEMA_VERSION;
    delete process.env.RSHAKE_ALERT_SHARED_SECRET;
    process.env.LOCALDBS_DIRECTORY = tempDir;
    process.env.RSHAKE_ALERT_MIN_INTERVAL_SEC = '0';
    process.env.RSHAKE_ALERT_COOLDOWN_STATE_FILE = path.join(tempDir, 'cooldown.json');
    process.env.RSHAKE_ALERT_QUEUE_FILE = path.join(tempDir, 'queue.json');

    deviceService.buildW1BaseUrl.mockReturnValue('http://central.example:5000');
    deviceService.syncRshakeAlertCredential.mockResolvedValue({ str: 'success' });
    deviceService.getStoredDeviceInfo.mockResolvedValue({
      network: 'am',
      station: 'abc1',
      streamId: 'AM_ABC1_.*/MSEED',
      latitude: 14.6,
      longitude: 121.04,
      elevation: 35.5,
    });
    utils.getHostDeviceConfig.mockReturnValue({});
    utils.read_mac_address.mockReturnValue('AA:BB:CC:DD:EE:FF');
    alertCredentialService.getStoredAlertSharedSecret.mockReturnValue('');
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('posts alert payload to central endpoint when enabled', async () => {
    axios.post.mockResolvedValue({ status: 202 });

    const result = await postRshakeAlert({
      type: 'device.alert',
      alertCode: 'STREAM_ERROR',
      severity: 'critical',
      status: 'Error',
      summary: 'Stream entered Error state.',
      details: { retryCount: 4 },
      dedupeKey: 'custom.stream-error',
    });

    expect(result).toEqual({ str: 'success', status: 202 });
    expect(axios.post).toHaveBeenCalledTimes(1);

    const [url, payload, options] = axios.post.mock.calls[0];
    expect(url).toBe('http://central.example:5000/messaging/restricted/rshake-alert');
    expect(options).toEqual({ timeout: 5000 });
    expect(payload).toMatchObject({
      schemaVersion: '1.0',
      type: 'device.alert',
      alertCode: 'STREAM_ERROR',
      severity: 'critical',
      status: 'Error',
      summary: 'Stream entered Error state.',
      dedupeKey: 'custom.stream-error',
      device: {
        network: 'AM',
        station: 'ABC1',
        streamId: 'AM_ABC1_.*/MSEED',
        macAddress: 'AA:BB:CC:DD:EE:FF',
      },
      location: {
        latitude: 14.6,
        longitude: 121.04,
        elevation: 35.5,
      },
      details: { retryCount: 4 },
    });
    expect(payload.messageId).toEqual(expect.any(String));
    expect(payload.occurredAt).toEqual(expect.any(String));
  });

  it('prefers host identity when station id changed on the device', async () => {
    axios.post.mockResolvedValue({ status: 202 });
    deviceService.getStoredDeviceInfo.mockResolvedValue({
      network: 'am',
      station: 'r690a',
      streamId: 'AM_R690A_.*/MSEED',
      latitude: 14.6,
      longitude: 121.04,
      elevation: 35.5,
    });
    utils.getHostDeviceConfig.mockReturnValue({
      network: 'AM',
      station: 'S690A',
      streamId: 'AM_S690A_.*/MSEED',
    });

    const result = await postRshakeAlert({
      type: 'device.alert',
      alertCode: 'STREAM_ERROR',
      severity: 'critical',
      status: 'Error',
      summary: 'Station id changed',
    });

    expect(result).toEqual({ str: 'success', status: 202 });
    const [, payload] = axios.post.mock.calls[0];
    expect(payload.device).toMatchObject({
      network: 'AM',
      station: 'S690A',
      streamId: 'AM_S690A_.*/MSEED',
      macAddress: 'AA:BB:CC:DD:EE:FF',
    });
  });

  it('adds shared-secret header when configured', async () => {
    alertCredentialService.getStoredAlertSharedSecret.mockReturnValue('sender-secret');
    axios.post.mockResolvedValue({ status: 202 });

    const result = await postRshakeAlert({
      type: 'device.alert',
      alertCode: 'STREAM_ERROR',
      severity: 'critical',
      status: 'Error',
      summary: 'Header test',
    });

    expect(result).toEqual({ str: 'success', status: 202 });
    const [, , options] = axios.post.mock.calls[0];
    expect(options).toEqual({
      timeout: 5000,
      headers: {
        'X-RShake-Alert-Secret': 'sender-secret',
      },
    });
  });

  it('syncs the issued credential and retries once after a 403 response', async () => {
    alertCredentialService.getStoredAlertSharedSecret
      .mockReturnValueOnce('')
      .mockReturnValue('rotated-secret');
    axios.post
      .mockRejectedValueOnce({
        response: {
          status: 403,
          data: { message: 'Forbidden' },
        },
      })
      .mockResolvedValueOnce({ status: 202 });

    const result = await postRshakeAlert({
      type: 'device.alert',
      alertCode: 'STREAM_ERROR',
      severity: 'critical',
      status: 'Error',
      summary: 'Retry after sync',
    });

    expect(result).toEqual({ str: 'success', status: 202 });
    expect(deviceService.syncRshakeAlertCredential).toHaveBeenCalledWith({
      allowTokenRefresh: true,
    });
    expect(axios.post).toHaveBeenCalledTimes(2);
    expect(axios.post.mock.calls[1][2]).toEqual({
      timeout: 5000,
      headers: {
        'X-RShake-Alert-Secret': 'rotated-secret',
      },
    });
  });

  it('does not post when alerts are disabled', async () => {
    process.env.RSHAKE_ALERTS_ENABLED = 'false';

    const result = await postRshakeAlert({
      type: 'device.alert',
      alertCode: 'STREAM_ERROR',
      severity: 'critical',
      status: 'Error',
      summary: 'Disabled test',
    });

    expect(result).toEqual({ str: 'disabled' });
    expect(axios.post).not.toHaveBeenCalled();
  });

  it('skips posting when no device identifiers are available', async () => {
    deviceService.getStoredDeviceInfo.mockResolvedValue({
      network: null,
      station: null,
      streamId: null,
      latitude: null,
      longitude: null,
      elevation: null,
    });
    utils.getHostDeviceConfig.mockReturnValue({});
    utils.read_mac_address.mockReturnValue('');

    const result = await postRshakeAlert({
      type: 'device.alert',
      alertCode: 'STREAM_ERROR',
      severity: 'critical',
      status: 'Error',
      summary: 'No identifiers',
    });

    expect(result).toEqual({
      str: 'skipped',
      reason: 'missingDeviceIdentifiers',
    });
    expect(axios.post).not.toHaveBeenCalled();
  });

  it('omits location object when coordinates are unavailable', async () => {
    axios.post.mockResolvedValue({ status: 202 });
    deviceService.getStoredDeviceInfo.mockResolvedValue({
      network: 'am',
      station: 'abc1',
      streamId: null,
      latitude: null,
      longitude: null,
      elevation: null,
    });
    utils.getHostDeviceConfig.mockReturnValue({});
    utils.read_mac_address.mockReturnValue('');

    await postRshakeAlert({
      type: 'device.recovery',
      alertCode: 'STREAM_RECOVERY',
      severity: 'info',
      status: 'Streaming',
      summary: 'Recovered',
    });

    const [, payload] = axios.post.mock.calls[0];
    expect(payload.device).toMatchObject({
      network: 'AM',
      station: 'ABC1',
    });
    expect(payload.location).toBeUndefined();
  });
});
