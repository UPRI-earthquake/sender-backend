const request = require('supertest');
process.env.NODE_ENV = 'test';

jest.mock('../src/services/device.service', () => {
  const actual = jest.requireActual('../src/services/device.service');
  return {
    ...actual,
    getUnlinkIdentifiers: jest.fn(),
    ensureValidAccessToken: jest.fn(),
    clearLocalLinkState: jest.fn(),
    requestLinkReset: jest.fn(),
  };
});

jest.mock('../src/controllers/stream.utils', () => {
  const actual = jest.requireActual('../src/controllers/stream.utils');
  return {
    ...actual,
    clearStreamsObject: jest.fn(),
  };
});

const deviceService = require('../src/services/device.service');
const streamUtils = require('../src/controllers/stream.utils');
const app = require('../src/app');

describe('POST /device/reset-link', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('returns 200 for successful reset', async () => {
    deviceService.getUnlinkIdentifiers.mockResolvedValue({
      streamId: 'AM_TEST_.*/MSEED',
      macAddress: 'AA:BB:CC:DD:EE:FF',
    });
    streamUtils.clearStreamsObject.mockResolvedValue('success');
    deviceService.ensureValidAccessToken.mockResolvedValue('token');
    deviceService.clearLocalLinkState.mockResolvedValue(undefined);
    deviceService.requestLinkReset.mockResolvedValue('success');

    const response = await request(app).post('/device/reset-link');
    expect(response.statusCode).toBe(200);
    expect(response.body?.payload?.remoteReset).toBe(true);
  });

  it('returns 400 when required identifiers are missing', async () => {
    deviceService.getUnlinkIdentifiers.mockResolvedValue({
      streamId: null,
      macAddress: null,
    });

    const response = await request(app).post('/device/reset-link');
    expect(response.statusCode).toBe(400);
  });
});
