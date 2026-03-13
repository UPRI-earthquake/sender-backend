const fs = require('fs');
const os = require('os');
const path = require('path');

const alertCredentialService = require('../src/services/alertCredential.service');

describe('alertCredential.service', () => {
  const originalEnv = process.env;
  let tempDir;
  let runtimeEnvFile;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sender-alert-credential-'));
    runtimeEnvFile = path.join(tempDir, 'alert.env');
    process.env = {
      ...originalEnv,
      RSHAKE_ALERT_RUNTIME_ENV_FILE: runtimeEnvFile,
    };
    delete process.env.RSHAKE_ALERT_SHARED_SECRET;
    delete process.env.RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT;
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('persists and reloads the shared secret from the runtime env file', async () => {
    await alertCredentialService.persistAlertSharedSecret('issued-secret', {
      issuedAt: '2026-03-13T00:00:00.000Z',
    });

    delete process.env.RSHAKE_ALERT_SHARED_SECRET;
    delete process.env.RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT;

    expect(alertCredentialService.getStoredAlertSharedSecret()).toBe('issued-secret');
    expect(fs.readFileSync(runtimeEnvFile, 'utf8')).toContain('RSHAKE_ALERT_SHARED_SECRET=issued-secret');
  });

  it('clears the shared secret from the runtime env file', async () => {
    await alertCredentialService.persistAlertSharedSecret('issued-secret');
    await alertCredentialService.clearAlertSharedSecret();

    expect(alertCredentialService.getStoredAlertSharedSecret()).toBe('');
    expect(fs.readFileSync(runtimeEnvFile, 'utf8')).toContain('RSHAKE_ALERT_SHARED_SECRET=');
  });
});
