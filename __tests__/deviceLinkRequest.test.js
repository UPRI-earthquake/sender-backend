const request = require('supertest');
let deviceService;

jest.mock('../src/services/device.service', () => {
  const actual = jest.requireActual('../src/services/device.service');
  return {
    ...actual,
    requestLinking: jest.fn().mockResolvedValue({
      accessToken: 'test-access-token',
      refreshToken: 'test-refresh-token',
      deviceInfo: { network: 'AM', station: 'TEST' },
      rshakeAlertCredential: {
        sharedSecret: 'issued-secret',
        issuedAt: '2026-03-13T00:00:00.000Z',
      },
    }),
    persistTokenPair: jest.fn().mockResolvedValue(undefined),
    persistAlertCredential: jest.fn().mockResolvedValue(undefined),
    syncRshakeAlertCredential: jest.fn().mockResolvedValue({ str: 'success' }),
  };
});

describe('POST /device/link', () => {
  let app;
  let consoleLogSpy;

  beforeAll(() => {
    jest.resetModules();
    process.env.NODE_ENV = 'test';
    consoleLogSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    deviceService = require('../src/services/device.service');
    app = require('../src/app');
  });

  afterAll(() => {
    if (consoleLogSpy) {
      consoleLogSpy.mockRestore();
    }
  });

  it('rejects missing username (401)', async () => {
    const response = await request(app).post('/device/link').send({
      username: '',
      password: 'test',
      latitude: '14.5995',
      longitude: '121.0424',
      elevation: '42.75',
    });
    expect(response.statusCode).toBe(401);
  });

  it('rejects missing password (401)', async () => {
    const response = await request(app).post('/device/link').send({
      username: 'test',
      password: '',
      latitude: '14.5995',
      longitude: '121.0424',
      elevation: '42.75',
    });
    expect(response.statusCode).toBe(401);
  });

  it('returns 200 for valid link request (mocked)', async () => {
    const response = await request(app).post('/device/link').send({
      username: 'test',
      password: 'test',
      latitude: '14.5995',
      longitude: '121.0424',
      elevation: '42.75',
    });
    expect(response.statusCode).toBe(200);
  });

  it('responds with JSON', async () => {
    const response = await request(app).post('/device/link').send({
      username: 'test',
      password: 'test',
      latitude: '14.5995',
      longitude: '121.0424',
      elevation: '42.75',
    });
    expect(response.headers['content-type']).toEqual(expect.stringContaining('json'));
  });

  it('persists the issued alert credential from the link response', async () => {
    await request(app).post('/device/link').send({
      username: 'test',
      password: 'test',
      latitude: '14.5995',
      longitude: '121.0424',
      elevation: '42.75',
    });

    expect(deviceService.persistAlertCredential).toHaveBeenCalledWith({
      sharedSecret: 'issued-secret',
      issuedAt: '2026-03-13T00:00:00.000Z',
    });
    expect(deviceService.syncRshakeAlertCredential).not.toHaveBeenCalled();
  });
});
