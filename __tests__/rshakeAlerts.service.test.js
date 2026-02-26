const axios = require('axios');

jest.mock('axios', () => ({
  post: jest.fn(),
}));

jest.mock('../src/services/device.service', () => ({
  buildW1BaseUrl: jest.fn(),
  getStoredDeviceInfo: jest.fn(),
}));

jest.mock('../src/services/utils', () => ({
  getHostDeviceConfig: jest.fn(),
  read_mac_address: jest.fn(),
}));

const deviceService = require('../src/services/device.service');
const utils = require('../src/services/utils');
const { postRshakeAlert } = require('../src/services/rshakeAlerts.service');

describe('rshakeAlerts.service', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.clearAllMocks();
    process.env = { ...originalEnv };
    delete process.env.RSHAKE_ALERTS_ENABLED;
    delete process.env.W1_RS_ALERT_PATH;
    delete process.env.RSHAKE_ALERT_POST_TIMEOUT_MS;
    delete process.env.RSHAKE_ALERT_SCHEMA_VERSION;

    deviceService.buildW1BaseUrl.mockReturnValue('http://central.example:5000');
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
