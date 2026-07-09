const request = require('supertest');
const fs = require('fs').promises;
const os = require('os');
const path = require('path');

describe('GET /health/metrics', () => {
  let app;
  let tempRoot;
  let tempLocalDbs;

  beforeAll(async () => {
    jest.resetModules();
    process.env.NODE_ENV = 'test';

    tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'sender-backend-health-metrics-'));
    tempLocalDbs = path.join(tempRoot, 'localDBs');
    await fs.mkdir(tempLocalDbs, { recursive: true });
    process.env.LOCALDBS_DIRECTORY = tempLocalDbs;

    app = require('../src/app');
  });

  afterAll(async () => {
    if (tempRoot) {
      await fs.rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('returns metrics payload', async () => {
    await request(app).get('/health/resources');
    const response = await request(app).get('/health/metrics');
    expect(response.statusCode).toBe(200);
    expect(response.body?.payload?.http?.requestsTotal).toBeGreaterThan(0);
    expect(response.body?.payload?.health?.checks).toBeDefined();
    expect(response.body?.payload?.health?.history).toBeDefined();
  });
});
