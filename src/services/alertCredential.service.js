const fs = require('fs');
const path = require('path');

function normalizeSecret(value) {
  return String(value || '').trim();
}

function shellQuote(value) {
  return `'${normalizeSecret(value).replace(/'/g, "'\\''")}'`;
}

function unquoteEnvValue(value) {
  const raw = String(value || '').trim();
  if (raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'")) {
    return raw
      .slice(1, -1)
      .split("'\\''")
      .join("'");
  }
  return raw;
}

function getRuntimeEnvPath() {
  const configured = normalizeSecret(
    process.env.RSHAKE_ALERT_RUNTIME_ENV_FILE || process.env.RSHAKE_ALERT_SHARED_SECRET_FILE,
  );
  return configured || null;
}

function parseEnvFile(raw = '') {
  const parsed = {};
  String(raw || '')
    .split(/\r?\n/)
    .forEach((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return;
      const separatorIndex = trimmed.indexOf('=');
      if (separatorIndex <= 0) return;
      const key = trimmed.slice(0, separatorIndex).trim();
      const value = unquoteEnvValue(trimmed.slice(separatorIndex + 1));
      if (!key) return;
      parsed[key] = value;
    });
  return parsed;
}

function getStoredAlertSharedSecret() {
  const fromEnv = normalizeSecret(process.env.RSHAKE_ALERT_SHARED_SECRET);
  if (fromEnv) {
    return fromEnv;
  }

  const filePath = getRuntimeEnvPath();
  if (!filePath) {
    return '';
  }

  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    const parsed = parseEnvFile(raw);
    const sharedSecret = normalizeSecret(parsed.RSHAKE_ALERT_SHARED_SECRET);
    if (sharedSecret) {
      process.env.RSHAKE_ALERT_SHARED_SECRET = sharedSecret;
    }
    if (parsed.RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT) {
      process.env.RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT = parsed.RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT;
    }
    return sharedSecret;
  } catch (_error) {
    return '';
  }
}

async function writeEnvFile({ sharedSecret = '', issuedAt = '' } = {}) {
  const filePath = getRuntimeEnvPath();
  if (!filePath) {
    return { persisted: false, path: null };
  }

  const dir = path.dirname(filePath);
  const baseName = path.basename(filePath);
  const tmpPath = path.join(dir, `.${baseName}.${process.pid}.${Date.now()}.tmp`);
  const lines = [
    '# Managed by sender-backend. Used for authenticated RShake alert posts.',
    `RSHAKE_ALERT_SHARED_SECRET=${shellQuote(sharedSecret)}`,
    `RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT=${shellQuote(issuedAt)}`,
  ];

  await fs.promises.mkdir(dir, { recursive: true });
  await fs.promises.writeFile(tmpPath, `${lines.join('\n')}\n`, { mode: 0o600 });
  await fs.promises.rename(tmpPath, filePath);
  try {
    await fs.promises.chmod(filePath, 0o600);
  } catch (_error) {
    // Best-effort only; some bind mounts may not allow chmod.
  }

  return { persisted: true, path: filePath };
}

async function persistAlertSharedSecret(sharedSecret, { issuedAt = '' } = {}) {
  const normalized = normalizeSecret(sharedSecret);
  if (!normalized) {
    return clearAlertSharedSecret();
  }

  process.env.RSHAKE_ALERT_SHARED_SECRET = normalized;
  if (issuedAt) {
    process.env.RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT = normalizeSecret(issuedAt);
  } else {
    delete process.env.RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT;
  }

  return writeEnvFile({
    sharedSecret: normalized,
    issuedAt: process.env.RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT || '',
  });
}

async function clearAlertSharedSecret() {
  delete process.env.RSHAKE_ALERT_SHARED_SECRET;
  delete process.env.RSHAKE_ALERT_SHARED_SECRET_ISSUED_AT;
  return writeEnvFile({ sharedSecret: '', issuedAt: '' });
}

module.exports = {
  getRuntimeEnvPath,
  getStoredAlertSharedSecret,
  persistAlertSharedSecret,
  clearAlertSharedSecret,
};
