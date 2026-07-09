const fs = require('fs').promises;
const os = require('os');
const path = require('path');

jest.mock('axios', () => ({
  get: jest.fn(),
  post: jest.fn(),
}));

describe('device identity resolution', () => {
  const originalEnv = process.env;
  let tempRoot;
  let tempLocalDbs;
  let tempSettings;
  let axios;
  let deviceService;

  beforeEach(async () => {
    jest.resetModules();
    process.env = { ...originalEnv };
    process.env.NODE_ENV = 'test';
    process.env.W1_DEV_IP = 'w1.test.local';
    process.env.W1_DEV_PORT = '8080';

    tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'sender-device-identity-'));
    tempLocalDbs = path.join(tempRoot, 'localDBs');
    tempSettings = path.join(tempRoot, 'settings');

    await fs.mkdir(tempLocalDbs, { recursive: true });
    await fs.mkdir(path.join(tempSettings, 'sys'), { recursive: true });

    process.env.LOCALDBS_DIRECTORY = tempLocalDbs;
    process.env.RSHAKE_SETTINGS_PATH = tempSettings;

    await fs.writeFile(path.join(tempSettings, 'sys', 'NET.txt'), 'AM');
    await fs.writeFile(path.join(tempSettings, 'sys', 'STN.txt'), 'S690A');
    await fs.writeFile(path.join(tempSettings, 'sys', 'eth-mac.txt'), 'AA:BB:CC:DD:EE:FF');

    await fs.writeFile(path.join(tempLocalDbs, 'deviceInfo.json'), JSON.stringify({
      network: 'AM',
      station: 'R690A',
      streamId: 'AM_R690A_.*/MSEED',
      longitude: null,
      latitude: null,
      elevation: null,
    }));

    await fs.writeFile(path.join(tempLocalDbs, 'token.json'), JSON.stringify({
      accessToken: 'dummy-token',
      refreshToken: null,
      accessTokenExpiresAt: null,
      refreshTokenExpiresAt: null,
    }));

    axios = require('axios');
    deviceService = require('../src/services/device.service');
  });

  afterEach(async () => {
    if (tempRoot) {
      await fs.rm(tempRoot, { recursive: true, force: true });
    }
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('uses host station/stream id but falls back to stored identity when host id is not linked', async () => {
    axios.get
      .mockRejectedValueOnce({ response: { status: 400 } })
      .mockResolvedValueOnce({ data: { payload: { status: 'linked' } } });

    const details = await deviceService.getDeviceDetails();

    expect(details.deviceInfo).toMatchObject({
      network: 'AM',
      station: 'S690A',
      streamId: 'AM_S690A_.*/MSEED',
    });
    expect(details.linkState).toBe('linked');

    expect(axios.get).toHaveBeenCalledTimes(2);
    expect(axios.get.mock.calls[0][0]).toContain('station=S690A');
    expect(axios.get.mock.calls[1][0]).toContain('station=R690A');
  });
});
