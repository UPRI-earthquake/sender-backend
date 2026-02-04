const request = require('supertest');
const fs = require('fs').promises;
const os = require('os');
const path = require('path');

jest.mock('../src/services/servers.service', () => ({
  requestRingserverHostsList: jest.fn().mockResolvedValue([
    { username: 'UPRI', ringserverUrl: 'https://example.invalid', ringserverPort: 18000 },
  ]),
}));

describe('Servers routes', () => {
  let app;
  let tempRoot;
  let tempLocalDbs;

  beforeAll(async () => {
    jest.resetModules();
    process.env.NODE_ENV = 'test';

    tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'sender-backend-test-'));
    tempLocalDbs = path.join(tempRoot, 'localDBs');
    await fs.mkdir(tempLocalDbs, { recursive: true });
    process.env.LOCALDBS_DIRECTORY = tempLocalDbs;

    await fs.writeFile(path.join(tempLocalDbs, 'deviceInfo.json'), '{}');

    app = require('../src/app');
  });

  afterAll(async () => {
    if (tempRoot) {
      await fs.rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('GET /servers/ringserver-hosts responds 200 (mocked)', async () => {
    const response = await request(app).get('/servers/ringserver-hosts');
    expect(response.statusCode).toBe(200);
  });

  it('POST /servers/remove rejects missing url (400)', async () => {
    const response = await request(app).post('/servers/remove').send({});
    expect(response.statusCode).toBe(400);
  });

  it('POST /servers/remove removes an existing url (200)', async () => {
    const existing = [
      { institutionName: 'Test', url: 'https://example.invalid' },
      { institutionName: 'Other', url: 'https://other.invalid' },
    ];
    await fs.writeFile(path.join(tempLocalDbs, 'servers.json'), JSON.stringify(existing));

    const response = await request(app).post('/servers/remove').send({ url: 'https://example.invalid' });
    expect(response.statusCode).toBe(200);

    const updated = JSON.parse(await fs.readFile(path.join(tempLocalDbs, 'servers.json'), 'utf-8'));
    expect(updated.find((entry) => entry.url === 'https://example.invalid')).toBeUndefined();
  });
});
