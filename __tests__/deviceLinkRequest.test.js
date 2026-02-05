const request = require('supertest');

jest.mock('../src/services/device.service', () => {
  const actual = jest.requireActual('../src/services/device.service');
  return {
    ...actual,
    requestLinking: jest.fn().mockResolvedValue({
      accessToken: 'test-access-token',
      refreshToken: 'test-refresh-token',
      deviceInfo: { network: 'AM', station: 'TEST' },
    }),
    persistTokenPair: jest.fn().mockResolvedValue(undefined),
  };
});

describe('POST /device/link', () => {
  let app;
  let consoleLogSpy;

  beforeAll(() => {
    jest.resetModules();
    process.env.NODE_ENV = 'test';
    consoleLogSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
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
});
