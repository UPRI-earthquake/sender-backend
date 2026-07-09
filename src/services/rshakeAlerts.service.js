const axios = require('axios');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const deviceService = require('./device.service');
const alertCredentialService = require('./alertCredential.service');
const utils = require('./utils');
const metricsService = require('./metrics.service');

const DEFAULT_ALERT_PATH = '/messaging/restricted/rshake-alert';
const DEFAULT_SCHEMA_VERSION = '1.0';
const DEFAULT_POST_TIMEOUT_MS = 5000;
const DEFAULT_QUEUE_DRAIN_LIMIT = 5;

const localDbDir = () => process.env.LOCALDBS_DIRECTORY || './localDBs';
const defaultQueueFile = () => path.join(localDbDir(), 'rshake-alert-queue.json');
const defaultCooldownStateFile = () => path.join(localDbDir(), 'rshake-alert-cooldown-state.json');

let queueLoaded = false;
let queueState = [];
let queueDrainInProgress = false;
let cooldownStateLoaded = false;
let cooldownState = {};

function parseBoolean(value, fallback = true) {
  if (value === undefined || value === null || value === '') return fallback;
  if (typeof value === 'boolean') return value;
  const normalized = String(value).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'off'].includes(normalized)) return false;
  return fallback;
}

function createMessageId() {
  if (typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return crypto.randomBytes(16).toString('hex');
}

function parseInteger(value, fallback, min = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  const normalized = Math.floor(parsed);
  if (normalized < min) return fallback;
  return normalized;
}

function getQueueFilePath() {
  const configured = String(process.env.RSHAKE_ALERT_QUEUE_FILE || '').trim();
  return configured || defaultQueueFile();
}

function getCooldownStateFilePath() {
  const configured = String(process.env.RSHAKE_ALERT_COOLDOWN_STATE_FILE || '').trim();
  return configured || defaultCooldownStateFile();
}

async function writeJsonAtomic(filePath, data) {
  const dir = path.dirname(filePath);
  const baseName = path.basename(filePath);
  const tmpPath = path.join(dir, `.${baseName}.${process.pid}.${Date.now()}.tmp`);
  await fs.promises.mkdir(dir, { recursive: true });
  await fs.promises.writeFile(tmpPath, JSON.stringify(data));
  await fs.promises.rename(tmpPath, filePath);
}

function shouldRetryAlertPost(error) {
  if (!error) return false;
  const status = error?.response?.status || null;
  if (status === 429 || (status !== null && status >= 500)) {
    return true;
  }

  const transientCodes = new Set([
    'ECONNABORTED',
    'ECONNRESET',
    'ENOTFOUND',
    'EAI_AGAIN',
    'ETIMEDOUT',
    'EHOSTUNREACH',
    'ENETUNREACH',
  ]);
  return transientCodes.has(error.code);
}

function buildRequestOptions() {
  const timeout = Number(process.env.RSHAKE_ALERT_POST_TIMEOUT_MS || DEFAULT_POST_TIMEOUT_MS);
  const requestOptions = {
    timeout: Number.isFinite(timeout) && timeout > 0 ? timeout : DEFAULT_POST_TIMEOUT_MS,
  };

  const headers = buildAlertHeaders();
  if (headers) {
    requestOptions.headers = headers;
  }
  return requestOptions;
}

async function postAlertWithRetries(alertUrl, payload) {
  const attempts = parseInteger(process.env.RSHAKE_ALERT_RETRY_ATTEMPTS, 0, 0);
  const baseBackoffMs = parseInteger(process.env.RSHAKE_ALERT_RETRY_BASE_MS, 500, 50);
  const requestOptions = buildRequestOptions();
  let lastError = null;

  for (let attempt = 0; attempt <= attempts; attempt += 1) {
    try {
      const response = await axios.post(alertUrl, payload, requestOptions);
      return { response };
    } catch (error) {
      lastError = error;
      if (attempt >= attempts || !shouldRetryAlertPost(error)) {
        break;
      }
      const waitMs = baseBackoffMs * (2 ** attempt);
      await new Promise((resolve) => setTimeout(resolve, waitMs));
    }
  }

  throw lastError;
}

function queueEnabled() {
  return parseBoolean(process.env.RSHAKE_ALERT_QUEUE_ENABLED, false);
}

async function loadQueueState() {
  if (queueLoaded) return;
  queueLoaded = true;
  if (!queueEnabled()) {
    queueState = [];
    return;
  }

  try {
    const raw = await fs.promises.readFile(getQueueFilePath(), 'utf-8');
    const parsed = JSON.parse(raw);
    queueState = Array.isArray(parsed) ? parsed : [];
  } catch (_error) {
    queueState = [];
  }
}

async function saveQueueState() {
  if (!queueEnabled()) return;
  try {
    await writeJsonAtomic(getQueueFilePath(), queueState);
  } catch (error) {
    console.log(`Failed to persist alert queue: ${error.message || error}`);
  }
}

async function enqueueAlert(payload) {
  if (!queueEnabled()) return false;
  await loadQueueState();

  const maxQueueSize = parseInteger(process.env.RSHAKE_ALERT_QUEUE_MAX_SIZE, 200, 1);
  const now = Date.now();
  queueState.push({
    id: createMessageId(),
    attempts: 0,
    nextAttemptAt: now,
    payload,
  });
  if (queueState.length > maxQueueSize) {
    queueState = queueState.slice(queueState.length - maxQueueSize);
  }
  await saveQueueState();
  return true;
}

async function loadCooldownState() {
  if (cooldownStateLoaded) return;
  cooldownStateLoaded = true;
  cooldownState = {};

  try {
    const raw = await fs.promises.readFile(getCooldownStateFilePath(), 'utf-8');
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') {
      cooldownState = parsed;
    }
  } catch (_error) {
    cooldownState = {};
  }
}

async function saveCooldownState() {
  try {
    await writeJsonAtomic(getCooldownStateFilePath(), cooldownState);
  } catch (error) {
    console.log(`Failed to persist alert cooldown state: ${error.message || error}`);
  }
}

function getMinAlertIntervalSec() {
  return parseInteger(process.env.RSHAKE_ALERT_MIN_INTERVAL_SEC, 0, 0);
}

async function shouldRateLimitAlert(dedupeKey) {
  const minIntervalSec = getMinAlertIntervalSec();
  if (minIntervalSec <= 0 || !dedupeKey) {
    return { limited: false, minIntervalSec: 0 };
  }

  await loadCooldownState();
  const nowSeconds = Math.floor(Date.now() / 1000);
  const lastSentAt = Number(cooldownState[dedupeKey] || 0);

  if (Number.isFinite(lastSentAt) && lastSentAt > 0) {
    const elapsed = nowSeconds - lastSentAt;
    if (elapsed < minIntervalSec) {
      return {
        limited: true,
        minIntervalSec,
        nextAllowedAt: lastSentAt + minIntervalSec,
      };
    }
  }

  return { limited: false, minIntervalSec };
}

async function markAlertSent(dedupeKey) {
  if (!dedupeKey || getMinAlertIntervalSec() <= 0) {
    return;
  }
  await loadCooldownState();
  cooldownState[dedupeKey] = Math.floor(Date.now() / 1000);
  await saveCooldownState();
}

async function drainQueuedAlerts({ limit = DEFAULT_QUEUE_DRAIN_LIMIT } = {}) {
  if (!queueEnabled()) return;
  if (queueDrainInProgress) return;

  queueDrainInProgress = true;
  try {
    await loadQueueState();
    if (!Array.isArray(queueState) || queueState.length === 0) {
      return;
    }

    const maxAttempts = parseInteger(process.env.RSHAKE_ALERT_QUEUE_MAX_ATTEMPTS, 20, 1);
    const baseBackoffMs = parseInteger(process.env.RSHAKE_ALERT_QUEUE_BACKOFF_MS, 30000, 1000);
    const now = Date.now();
    const alertUrl = buildAlertUrl();
    let processed = 0;
    let changed = false;
    const nextQueue = [];

    for (const item of queueState) {
      if (processed >= limit) {
        nextQueue.push(item);
        continue;
      }

      const nextAttemptAt = Number(item?.nextAttemptAt || 0);
      if (nextAttemptAt > now) {
        nextQueue.push(item);
        continue;
      }

      processed += 1;
      try {
        await postAlertWithRetries(alertUrl, item.payload);
        await markAlertSent(item?.payload?.dedupeKey);
        changed = true;
      } catch (error) {
        const attempts = parseInteger(item?.attempts, 0, 0) + 1;
        if (attempts >= maxAttempts || !shouldRetryAlertPost(error)) {
          changed = true;
          continue;
        }

        nextQueue.push({
          ...item,
          attempts,
          nextAttemptAt: now + (baseBackoffMs * attempts),
        });
        changed = true;
      }
    }

    if (nextQueue.length !== queueState.length || changed) {
      queueState = nextQueue;
      await saveQueueState();
    }
  } finally {
    queueDrainInProgress = false;
  }
}

function normalizeAlertPath() {
  const raw = String(process.env.W1_RS_ALERT_PATH || DEFAULT_ALERT_PATH).trim();
  if (!raw) return DEFAULT_ALERT_PATH;
  return raw.startsWith('/') ? raw : `/${raw}`;
}

function buildAlertUrl() {
  const baseUrl = String(deviceService.buildW1BaseUrl() || '').replace(/\/+$/g, '');
  return `${baseUrl}${normalizeAlertPath()}`;
}

function buildAlertHeaders() {
  const sharedSecret = alertCredentialService.getStoredAlertSharedSecret();
  if (!sharedSecret) {
    return undefined;
  }
  return {
    'X-RShake-Alert-Secret': sharedSecret,
  };
}

async function retryAfterCredentialSync(error, alertUrl, payload) {
  if (error?.response?.status !== 403) {
    return null;
  }

  try {
    const syncResult = await deviceService.syncRshakeAlertCredential({
      allowTokenRefresh: true,
    });
    if (syncResult?.str !== 'success') {
      return null;
    }
    return postAlertWithRetries(alertUrl, payload);
  } catch (syncError) {
    console.log(`RShake alert credential sync failed after 403: ${syncError?.message || syncError}`);
    return null;
  }
}

function sanitizeIdentifier(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function normalizeString(value, { uppercase = false } = {}) {
  if (value === null || value === undefined) {
    return '';
  }
  const trimmed = String(value).trim();
  if (!trimmed) {
    return '';
  }
  return uppercase ? trimmed.toUpperCase() : trimmed;
}

function normalizeNumber(value) {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
}

function buildStreamIdFromFields(network, station) {
  if (!network || !station) {
    return '';
  }
  return `${network}_${station}_.*/MSEED`;
}

function resolvePreferredDeviceIdentity(storedInfo = {}, hostConfig = {}) {
  const hostNetwork = normalizeString(hostConfig?.network, { uppercase: true });
  const hostStation = normalizeString(hostConfig?.station, { uppercase: true });
  const hostStreamId = normalizeString(hostConfig?.streamId || buildStreamIdFromFields(hostConfig?.network, hostConfig?.station));

  const storedNetwork = normalizeString(storedInfo?.network, { uppercase: true });
  const storedStation = normalizeString(storedInfo?.station, { uppercase: true });
  const storedStreamId = normalizeString(storedInfo?.streamId || buildStreamIdFromFields(storedInfo?.network, storedInfo?.station));

  return {
    network: hostNetwork || storedNetwork,
    station: hostStation || storedStation,
    streamId: hostStreamId || storedStreamId,
  };
}

function compactObject(objectValue = {}) {
  const compacted = {};
  Object.keys(objectValue).forEach((key) => {
    const value = objectValue[key];
    if (value === null || value === undefined || value === '') {
      return;
    }
    compacted[key] = value;
  });
  return compacted;
}

async function buildDeviceEnvelope() {
  const storedInfo = await deviceService.getStoredDeviceInfo();
  const hostConfig = utils.getHostDeviceConfig() || {};
  const macAddress = normalizeString(utils.read_mac_address());
  const identity = resolvePreferredDeviceIdentity(storedInfo, hostConfig);

  const device = compactObject({
    network: identity.network,
    station: identity.station,
    streamId: identity.streamId,
    macAddress,
  });

  const location = compactObject({
    latitude: normalizeNumber(storedInfo?.latitude ?? hostConfig?.latitude),
    longitude: normalizeNumber(storedInfo?.longitude ?? hostConfig?.longitude),
    elevation: normalizeNumber(storedInfo?.elevation ?? hostConfig?.elevation),
  });

  const hasDeviceIdentifier = Object.keys(device).length > 0;

  return {
    device,
    location,
    hasDeviceIdentifier,
  };
}

async function postRshakeAlert({
  type,
  alertCode,
  severity,
  status,
  summary,
  details = {},
  dedupeKey,
}) {
  const enabled = parseBoolean(process.env.RSHAKE_ALERTS_ENABLED, true);
  if (!enabled) {
    metricsService.recordAlertPost('disabled');
    return { str: 'disabled' };
  }

  const { device, location, hasDeviceIdentifier } = await buildDeviceEnvelope();
  if (!hasDeviceIdentifier) {
    metricsService.recordAlertPost('skipped', { reason: 'missingDeviceIdentifiers' });
    return {
      str: 'skipped',
      reason: 'missingDeviceIdentifiers',
    };
  }

  const identity =
    device.streamId
    || ((device.network && device.station) ? `${device.network}.${device.station}` : '')
    || device.macAddress
    || 'unknown-device';
  const fallbackDedupeKey = `${sanitizeIdentifier(identity)}.${sanitizeIdentifier(alertCode || 'alert')}`;
  const resolvedDedupeKey = dedupeKey || fallbackDedupeKey;

  const safeDetails = (details && typeof details === 'object') ? details : {};
  const payload = {
    schemaVersion: process.env.RSHAKE_ALERT_SCHEMA_VERSION || DEFAULT_SCHEMA_VERSION,
    messageId: createMessageId(),
    type,
    occurredAt: new Date().toISOString(),
    device,
    status,
    alertCode,
    severity,
    summary,
    dedupeKey: resolvedDedupeKey,
  };
  if (Object.keys(location).length > 0) {
    payload.location = location;
  }
  if (Object.keys(safeDetails).length > 0) {
    payload.details = safeDetails;
  }

  drainQueuedAlerts({ limit: DEFAULT_QUEUE_DRAIN_LIMIT }).catch((error) => {
    console.log(`Queued alert drain failed: ${error?.message || error}`);
  });

  const rateLimit = await shouldRateLimitAlert(resolvedDedupeKey);
  if (rateLimit.limited) {
    metricsService.recordAlertPost('rateLimited', { dedupeKey: resolvedDedupeKey });
    return {
      str: 'skipped',
      reason: 'rateLimited',
      dedupeKey: resolvedDedupeKey,
      nextAllowedAt: rateLimit.nextAllowedAt || null,
      minIntervalSec: rateLimit.minIntervalSec || 0,
    };
  }

  const alertUrl = buildAlertUrl();
  try {
    let postResult;
    try {
      postResult = await postAlertWithRetries(alertUrl, payload);
    } catch (error) {
      const retryResult = await retryAfterCredentialSync(error, alertUrl, payload);
      if (!retryResult) {
        throw error;
      }
      postResult = retryResult;
    }

    const { response } = postResult;
    await markAlertSent(resolvedDedupeKey);
    metricsService.recordAlertPost('success', { status: response.status });
    return { str: 'success', status: response.status };
  } catch (error) {
    const statusCode = error?.response?.status || null;
    const reason = error?.response?.data?.message || error?.message || String(error);
    console.log(`RShake alert post failed (${statusCode || 'no-status'}): ${reason}`);

    const queued = await enqueueAlert(payload);
    metricsService.recordAlertPost('error', {
      status: statusCode,
      queued,
    });
    if (queued) {
      metricsService.recordAlertPost('queued');
      drainQueuedAlerts({ limit: DEFAULT_QUEUE_DRAIN_LIMIT }).catch((drainError) => {
        console.log(`Queued alert drain failed: ${drainError?.message || drainError}`);
      });
    }

    return {
      str: 'error',
      status: statusCode,
      reason,
      queued,
    };
  }
}

module.exports = {
  postRshakeAlert,
};
