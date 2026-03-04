const axios = require('axios');
const crypto = require('crypto');
const deviceService = require('./device.service');
const utils = require('./utils');

const DEFAULT_ALERT_PATH = '/messaging/restricted/rshake-alert';
const DEFAULT_SCHEMA_VERSION = '1.0';
const DEFAULT_POST_TIMEOUT_MS = 5000;

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
  const sharedSecret = String(process.env.RSHAKE_ALERT_SHARED_SECRET || '').trim();
  if (!sharedSecret) {
    return undefined;
  }
  return {
    'X-RShake-Alert-Secret': sharedSecret,
  };
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

  const device = compactObject({
    network: normalizeString(storedInfo?.network || hostConfig?.network, { uppercase: true }),
    station: normalizeString(storedInfo?.station || hostConfig?.station, { uppercase: true }),
    streamId: normalizeString(storedInfo?.streamId || hostConfig?.streamId),
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
    return { str: 'disabled' };
  }

  const { device, location, hasDeviceIdentifier } = await buildDeviceEnvelope();
  if (!hasDeviceIdentifier) {
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
    dedupeKey: dedupeKey || fallbackDedupeKey,
  };
  if (Object.keys(location).length > 0) {
    payload.location = location;
  }
  if (Object.keys(safeDetails).length > 0) {
    payload.details = safeDetails;
  }

  const timeout = Number(process.env.RSHAKE_ALERT_POST_TIMEOUT_MS || DEFAULT_POST_TIMEOUT_MS);
  try {
    const requestOptions = {
      timeout: Number.isFinite(timeout) && timeout > 0 ? timeout : DEFAULT_POST_TIMEOUT_MS,
    };
    const headers = buildAlertHeaders();
    if (headers) {
      requestOptions.headers = headers;
    }

    const response = await axios.post(buildAlertUrl(), payload, {
      ...requestOptions,
    });
    return { str: 'success', status: response.status };
  } catch (error) {
    const statusCode = error?.response?.status || null;
    const reason = error?.response?.data?.message || error?.message || String(error);
    console.log(`RShake alert post failed (${statusCode || 'no-status'}): ${reason}`);
    return {
      str: 'error',
      status: statusCode,
      reason,
    };
  }
}

module.exports = {
  postRshakeAlert,
};
