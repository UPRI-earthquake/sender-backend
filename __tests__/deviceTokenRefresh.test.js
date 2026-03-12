const request = require('supertest');
process.env.NODE_ENV = 'test';

jest.mock('../src/services/device.service', () => {
  const actual = jest.requireActual('../src/services/device.service');
  return {
    ...actual,
    refreshAuthToken: jest.fn(),
    getAccessTokenStatus: jest.fn(),
    getRefreshTokenStatus: jest.fn(),
  };
});

const deviceService = require('../src/services/device.service');
const app = require('../src/app');

describe('POST /device/refresh-token', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('returns 200 when token refresh succeeds', async () => {
    deviceService.refreshAuthToken.mockResolvedValue('new-token');
    deviceService.getAccessTokenStatus.mockResolvedValue({ state: 'valid', accessTokenPresent: true });
    deviceService.getRefreshTokenStatus.mockResolvedValue({ state: 'valid', refreshTokenPresent: true });

    const response = await request(app).post('/device/refresh-token');
    expect(response.statusCode).toBe(200);
    expect(response.body?.payload?.tokenStatus?.state).toBe('valid');
    expect(response.body?.payload?.refreshTokenStatus?.state).toBe('valid');
  });

  it('returns 409 when relink is required', async () => {
    const relinkError = new Error('Relink required');
    relinkError.code = 'RELINK_REQUIRED';
    deviceService.refreshAuthToken.mockRejectedValue(relinkError);
    deviceService.getRefreshTokenStatus.mockResolvedValue({ state: 'expired' });

    const response = await request(app).post('/device/refresh-token');
    expect(response.statusCode).toBe(409);
    expect(response.body?.payload?.refreshTokenStatus?.state).toBe('expired');
  });
});
