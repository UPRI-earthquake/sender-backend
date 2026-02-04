const request = require('supertest');
const fs = require('fs').promises;
const os = require('os');
const path = require('path');

describe('GET /device/info', () => {
  let app;
  let tempRoot;
  let tempLocalDbs;
  let tempSettings;

  beforeAll(async () => {
    jest.resetModules();
    process.env.NODE_ENV = 'test';

    tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'sender-backend-test-'));
    tempLocalDbs = path.join(tempRoot, 'localDBs');
    tempSettings = path.join(tempRoot, 'settings');
    await fs.mkdir(tempLocalDbs, { recursive: true });
    await fs.mkdir(tempSettings, { recursive: true });

    process.env.LOCALDBS_DIRECTORY = tempLocalDbs;
    process.env.RSHAKE_SETTINGS_PATH = tempSettings;

    await fs.mkdir(path.join(tempSettings, 'sys'), { recursive: true });
    await fs.writeFile(path.join(tempSettings, 'sys', 'NET.txt'), '');
    await fs.writeFile(path.join(tempSettings, 'sys', 'STN.txt'), '');
    await fs.writeFile(path.join(tempLocalDbs, 'deviceInfo.json'), '{}');
    await fs.writeFile(path.join(tempLocalDbs, 'token.json'), JSON.stringify({
      accessToken: null,
      refreshToken: null,
      accessTokenExpiresAt: null,
      refreshTokenExpiresAt: null,
    }));

    app = require('../src/app');
  });

  afterAll(async () => {
    if (tempRoot) {
      await fs.rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('responds with 200', async () => {
    const response = await request(app).get('/device/info');
    expect(response.statusCode).toBe(200);
  });

  it('returns device info payload with token/link fields', async () => {
    const response = await request(app).get('/device/info');
    expect(response.body).not.toBeNull();
    expect(typeof response.body).toBe('object');
    expect(response.body.payload).toBeDefined();

    const { payload } = response.body;
    expect(payload).toHaveProperty('linked');
    expect(payload).toHaveProperty('hostConfig');
    expect(payload).toHaveProperty('tokenStatus');
    expect(payload).toHaveProperty('refreshTokenStatus');
    expect(payload).toHaveProperty('linkState');
  });
});
