const fs = require('fs');
const axios = require('axios');
const https = require('https');
const jwt = require('jsonwebtoken');
const httpsAgent = new https.Agent({ rejectUnauthorized: false });
const utils = require('./utils');

const localDbPath = (fileName) => `${process.env.LOCALDBS_DIRECTORY || './localDBs'}/${fileName}`;
const tokenPath = () => localDbPath('token.json');
const deviceInfoPath = () => localDbPath('deviceInfo.json');
const serversPath = () => localDbPath('servers.json');

const refreshIntervalMs = Number(process.env.REFRESH_CHECK_INTERVAL_MS || 15 * 60 * 1000); // default 15 minutes
const refreshLeewayMs = Number(process.env.REFRESH_EXPIRY_LEEWAY_MS || 10 * 60 * 1000); // default 10 minutes
const refreshPath = process.env.W1_REFRESH_PATH || '/device/refresh-token';

const defaultTokenInfo = {
  accessToken: null,
  refreshToken: null,
  accessTokenExpiresAt: null,
  refreshTokenExpiresAt: null,
};

const createDefaultTokenInfo = () => ({ ...defaultTokenInfo });

const defaultDeviceInfo = {
  network: null,
  station: null,
  location: null,
  channel: null,
  elevation: null,
  longitude: null,
  latitude: null,
  streamId: null,
};

const tokenLeewaySeconds = 300; // refresh tokens 5 minutes before expiry
const refreshTokenLeewaySeconds = Number(process.env.REFRESH_TOKEN_LEEWAY_SECONDS || 24 * 60 * 60); // default 24h leeway for refresh tokens
const RELINK_REQUIRED_ERROR_CODE = 'RELINK_REQUIRED';

function formatRelinkMessage(reason) {
  if (!reason) {
    return 'Device link expired. Relink the device to continue streaming.';
  }
  const trimmed = String(reason).trim();
  const suffix = trimmed.endsWith('.') ? '' : '.';
  return `${trimmed}${suffix} Relink the device to continue streaming.`;
}

function createRelinkRequiredError(reason, meta = {}) {
  const error = new Error(formatRelinkMessage(reason));
  error.code = RELINK_REQUIRED_ERROR_CODE;
  if (meta && typeof meta === 'object' && Object.keys(meta).length > 0) {
    error.meta = meta;
  }
  return error;
}

function unwrapDeviceInfo(payload) {
  if (!payload || typeof payload !== 'object') {
    return null;
  }
  if (payload.deviceInfo && typeof payload.deviceInfo === 'object') {
    return payload.deviceInfo;
  }
  return payload;
}

function roundToDecimals(value, decimals = 2) {
  if (value === null || value === undefined || value === '') return null;
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return value;
  const factor = 10 ** decimals;
  return Math.round(numeric * factor) / factor;
}

function decodeToken(accessToken) {
  if (!accessToken) return null;
  try {
    return jwt.decode(accessToken);
  } catch (error) {
    console.log(`Token decode error: ${error}`);
    return null;
  }
}

function isTokenExpiring(accessToken, leewaySeconds = tokenLeewaySeconds) {
  const decoded = decodeToken(accessToken);
  if (!decoded || !decoded.exp) {
    return true;
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  return decoded.exp - nowSeconds <= leewaySeconds;
}

function describeTokenStatus(tokenValue, {
  missingReason = 'Token missing',
  invalidReason = 'Unable to decode token',
  expiredReason = 'Token expired',
  presentKey = null,
  leewaySeconds = tokenLeewaySeconds,
} = {}) {
  const nowSeconds = Math.floor(Date.now() / 1000);

  if (!tokenValue || typeof tokenValue !== 'string' || tokenValue.trim().length === 0) {
    return {
      state: 'missing',
      reason: missingReason,
      checkedAt: nowSeconds,
    };
  }

  const decoded = decodeToken(tokenValue);
  if (!decoded || !decoded.exp) {
    const base = {
      state: 'invalid',
      reason: invalidReason,
      checkedAt: nowSeconds,
    };
    if (presentKey) {
      base[presentKey] = true;
    }
    return base;
  }

  const secondsToExpiry = decoded.exp - nowSeconds;
  const base = {
    expiresAt: decoded.exp,
    secondsToExpiry,
    checkedAt: nowSeconds,
  };
  if (presentKey) {
    base[presentKey] = true;
  }

  if (secondsToExpiry <= 0) {
    return {
      ...base,
      state: 'expired',
      reason: expiredReason,
    };
  }

  return {
    ...base,
    state: 'valid',
    expiringSoon: secondsToExpiry <= leewaySeconds,
  };
}

async function readJsonFile(filePath, fallback) {
  try {
    const contents = await fs.promises.readFile(filePath, 'utf-8');
    return JSON.parse(contents);
  } catch (error) {
    console.log(`Error reading ${filePath}: ${error}`);
    return fallback;
  }
}

async function writeJsonFile(filePath, data) {
  await fs.promises.writeFile(filePath, JSON.stringify(data));
}

function normalizeDeviceInfo(rawData) {
  if (!rawData) return { ...defaultDeviceInfo };
  const merged = rawData.deviceInfo ? { ...rawData.deviceInfo } : { ...rawData };
  const normalized = { ...defaultDeviceInfo, ...merged };

  ['longitude', 'latitude', 'elevation'].forEach((key) => {
    normalized[key] = roundToDecimals(normalized[key]);
  });

  return normalized;
}

function normalizeHostConfig(hostConfig) {
  if (!hostConfig) return hostConfig;
  return {
    ...hostConfig,
    longitude: roundToDecimals(hostConfig.longitude),
    latitude: roundToDecimals(hostConfig.latitude),
    elevation: roundToDecimals(hostConfig.elevation),
  };
}

function formatCoordinate(value) {
  const rounded = roundToDecimals(value);
  if (rounded === null || rounded === undefined) return value;
  return String(rounded);
}

async function persistDeviceInfo(deviceInfo, { overwrite = false } = {}) {
  const flattened = unwrapDeviceInfo(deviceInfo);
  if (!flattened || typeof flattened !== 'object') {
    return getStoredDeviceInfo();
  }

  const normalized = normalizeDeviceInfo(flattened);

  if (overwrite) {
    await writeJsonFile(deviceInfoPath(), normalized);
    return normalized;
  }

  const existing = await getStoredDeviceInfo();
  const updated = { ...existing };

  Object.keys(flattened).forEach((key) => {
    if (Object.prototype.hasOwnProperty.call(normalized, key)) {
      updated[key] = normalized[key];
    }
  });

  await writeJsonFile(deviceInfoPath(), updated);
  return updated;
}

async function persistToken(accessToken, refreshToken = null) {
  const tokenInfo = createDefaultTokenInfo();
  tokenInfo.accessToken = accessToken || null;
  tokenInfo.refreshToken = refreshToken || null;

  const decodedAccess = decodeToken(accessToken);
  if (decodedAccess?.exp) {
    tokenInfo.accessTokenExpiresAt = decodedAccess.exp;
  }

  const decodedRefresh = decodeToken(refreshToken);
  if (decodedRefresh?.exp) {
    tokenInfo.refreshTokenExpiresAt = decodedRefresh.exp;
  }

  await writeJsonFile(tokenPath(), tokenInfo);
  return tokenInfo;
}

async function persistTokenPair({ accessToken, refreshToken, deviceInfo }) {
  const tokenInfo = await persistToken(accessToken, refreshToken);
  if (deviceInfo) {
    const flattened = unwrapDeviceInfo(deviceInfo);
    const overwrite = Boolean(flattened && Object.prototype.hasOwnProperty.call(flattened, 'streamId'));
    await persistDeviceInfo(deviceInfo, { overwrite });
  }
  return tokenInfo;
}

async function getStoredDeviceInfo() {
  const stored = await readJsonFile(deviceInfoPath(), defaultDeviceInfo);
  return normalizeDeviceInfo(stored);
}

function buildW1BaseUrl() {
  return (process.env.NODE_ENV === 'production')
    ? `https://${process.env.W1_PROD_IP}`
    : `http://${process.env.W1_DEV_IP}:${process.env.W1_DEV_PORT}`;
}

// Function for checking if a jwt access token is already saved 
async function checkAuthToken() {
  const data = await readJsonFile(tokenPath(), createDefaultTokenInfo());
  if (!data?.accessToken) {
    throw new Error('No stored access token');
  }
  return data.accessToken;
}

async function getAccessTokenStatus() {
  const checkedAt = Math.floor(Date.now() / 1000);
  try {
    const rawContents = await fs.promises.readFile(tokenPath(), 'utf-8');
    let parsed;
    try {
      parsed = JSON.parse(rawContents);
    } catch (error) {
      return {
        state: 'corrupted',
        reason: 'token.json is not valid JSON',
        details: error.message,
        checkedAt,
      };
    }

    return describeTokenStatus(parsed?.accessToken, {
      missingReason: 'No access token saved.',
      invalidReason: 'Unable to decode access token',
      expiredReason: 'Access token expired',
      presentKey: 'accessTokenPresent',
      leewaySeconds: tokenLeewaySeconds,
    });
  } catch (error) {
    if (error.code === 'ENOENT') {
      return {
        state: 'missing',
        reason: 'Token file not found',
        checkedAt,
      };
    }
    return {
      state: 'corrupted',
      reason: 'Unable to read token file',
      details: error.message,
      checkedAt,
    };
  }
}

async function getRefreshTokenStatus() {
  const checkedAt = Math.floor(Date.now() / 1000);
  try {
    const rawContents = await fs.promises.readFile(tokenPath(), 'utf-8');
    let parsed;
    try {
      parsed = JSON.parse(rawContents);
    } catch (error) {
      return {
        state: 'corrupted',
        reason: 'token.json is not valid JSON',
        details: error.message,
        checkedAt,
      };
    }

    return describeTokenStatus(parsed?.refreshToken, {
      missingReason: 'No refresh token saved',
      invalidReason: 'Unable to decode refresh token',
      expiredReason: 'Refresh token expired',
      presentKey: 'refreshTokenPresent',
      leewaySeconds: refreshTokenLeewaySeconds,
    });
  } catch (error) {
    if (error.code === 'ENOENT') {
      return {
        state: 'missing',
        reason: 'Token file not found',
        checkedAt,
      };
    }
    return {
      state: 'corrupted',
      reason: 'Unable to read token file',
      details: error.message,
      checkedAt,
    };
  }
}

async function ensureValidAccessToken() {
  const tokenData = await readJsonFile(tokenPath(), createDefaultTokenInfo());
  if (tokenData?.accessToken) {
    if (!isTokenExpiring(tokenData.accessToken)) {
      return tokenData.accessToken;
    }
  }

  return refreshAuthToken();
}

async function refreshAuthToken() {
  const [tokenData, refreshTokenStatus] = await Promise.all([
    readJsonFile(tokenPath(), createDefaultTokenInfo()),
    getRefreshTokenStatus(),
  ]);

  const refreshToken = tokenData?.refreshToken;
  const refreshState = refreshTokenStatus?.state;
  const unusableStates = ['missing', 'invalid', 'expired', 'corrupted'];

  if (!refreshToken || unusableStates.includes(refreshState)) {
    throw createRelinkRequiredError(
      refreshTokenStatus?.reason || 'Refresh token unavailable',
      { refreshTokenStatus },
    );
  }

  const payload = await requestRefreshToken(refreshToken);

  if (!payload?.accessToken) {
    throw new Error('Refresh token response missing access token');
  }

  await persistTokenPair({
    accessToken: payload.accessToken,
    refreshToken: payload.refreshToken || refreshToken,
    deviceInfo: payload.deviceInfo,
  });

  return payload.accessToken;
}

async function refreshIfExpiringSoon() {
  const tokenData = await readJsonFile(tokenPath(), createDefaultTokenInfo());
  const [status, refreshStatus] = await Promise.all([
    getAccessTokenStatus(),
    getRefreshTokenStatus(),
  ]);

  if (['missing', 'invalid', 'expired', 'corrupted'].includes(refreshStatus.state)) {
    return null;
  }

  // If token missing/invalid/expired, try refresh immediately
  if (['missing', 'invalid', 'corrupted', 'expired'].includes(status.state)) {
    return refreshAuthToken();
  }

  // If token exists but expiring soon per configured leeway, refresh
  if (status.state === 'valid' && typeof status.secondsToExpiry === 'number') {
    const msToExpiry = status.secondsToExpiry * 1000;
    if (msToExpiry <= refreshLeewayMs) {
      return refreshAuthToken();
    }
  }

  return tokenData?.accessToken || null;
}

async function clearLocalLinkState() {
  await persistTokenPair({ accessToken: null, refreshToken: null, deviceInfo: defaultDeviceInfo });
  await writeJsonFile(serversPath(), []);
}

async function getDeviceDetails() {
  const hostConfig = normalizeHostConfig(utils.getHostDeviceConfig());
  const storedInfo = await getStoredDeviceInfo();
  const token = await readJsonFile(tokenPath(), createDefaultTokenInfo());
  const tokenStatus = await getAccessTokenStatus();
  const refreshTokenStatus = await getRefreshTokenStatus();

  const mergedDevice = {
    network: storedInfo.network || hostConfig.network,
    station: storedInfo.station || hostConfig.station,
    longitude: storedInfo.longitude ?? hostConfig.longitude,
    latitude: storedInfo.latitude ?? hostConfig.latitude,
    elevation: storedInfo.elevation ?? hostConfig.elevation,
    streamId: storedInfo.streamId || hostConfig.streamId,
  };

  return {
    deviceInfo: mergedDevice,
    hostConfig,
    linked: Boolean(storedInfo.streamId && token?.accessToken),
    tokenStatus,
    refreshTokenStatus,
  };
}

async function refreshDeviceMetadataFromHost() {
  const hostConfig = normalizeHostConfig(utils.getHostDeviceConfig());

  if (!hostConfig) {
    const err = new Error('Unable to read RShake host config');
    err.code = 'HOST_CONFIG_UNAVAILABLE';
    throw err;
  }

  const updates = {};
  const updatableKeys = ['network', 'station', 'longitude', 'latitude', 'elevation', 'streamId'];

  updatableKeys.forEach((key) => {
    const value = hostConfig[key];
    if (value !== null && value !== undefined && value !== '') {
      updates[key] = value;
    }
  });

  if (Object.keys(updates).length === 0) {
    const err = new Error('RShake config missing metadata to import');
    err.code = 'HOST_CONFIG_EMPTY';
    throw err;
  }

  await persistDeviceInfo(updates, { overwrite: false });
  return getDeviceDetails();
}

async function getUnlinkIdentifiers() {
  const storedInfo = await getStoredDeviceInfo();
  const hostConfig = normalizeHostConfig(utils.getHostDeviceConfig());

  const streamIdFromStoredFields = (storedInfo.network && storedInfo.station)
    ? `${storedInfo.network}_${storedInfo.station}_.*/MSEED`
    : null;

  const streamId = storedInfo.streamId
    || streamIdFromStoredFields
    || hostConfig?.streamId
    || utils.generate_streamId();

  const macAddress = utils.read_mac_address() || null;

  return {
    macAddress,
    streamId,
    network: storedInfo.network || hostConfig?.network || null,
    station: storedInfo.station || hostConfig?.station || null,
  };
}

async function requestRefreshToken(refreshToken) {
  if (!refreshToken) {
    throw createRelinkRequiredError('Refresh token missing or unavailable');
  }

  const url = `${buildW1BaseUrl()}${refreshPath}`;

  try {
    const response = await axios.post(url, { refreshToken });
    const payload = extractPayload(response.data);
    if (!payload || typeof payload !== 'object') {
      throw new Error('W1 refresh endpoint response missing payload');
    }
    return payload; // expect { accessToken, refreshToken?, deviceInfo? }
  } catch (error) {
    console.log(`Refresh token request error: ${error}`);
    if (error?.code === RELINK_REQUIRED_ERROR_CODE) {
      throw error;
    }
    if (error?.response && [400, 401, 403, 409].includes(error.response.status)) {
      const reason = error.response?.data?.message || 'Refresh token rejected by Earthquake Hub';
      throw createRelinkRequiredError(reason, { status: error.response.status });
    }
    throw error;
  }
}

// Function for adding the device to db in W1 and linking it to the user input account details
function extractPayload(envelope) {
  if (!envelope || typeof envelope !== 'object') {
    return null;
  }

  if (envelope.payload && typeof envelope.payload === 'object') {
    return envelope.payload;
  }

  return envelope;
}

async function requestLinking(userInput) {
  try {
    const streamId = utils.generate_streamId();
    const macAddress = utils.read_mac_address();

    const json = {
      username: userInput.username,
      password: userInput.password,
      role: 'sensor',
      longitude: formatCoordinate(userInput.longitude),
      latitude: formatCoordinate(userInput.latitude),
      elevation: formatCoordinate(userInput.elevation),
      macAddress: macAddress,
      streamId: streamId,
    };
    const url = `${buildW1BaseUrl()}/device/link`;

    const response = await axios.post(url, json, {
      httpsAgent,
    })

    const payload = extractPayload(response.data);
    if (!payload || typeof payload !== 'object') {
      throw new Error('W1 /device/link response missing payload');
    }

    return payload; // The device information obtained from the response
  } catch (error) {
    console.log("requestLinking error:" + error);
    throw error; // Send the error to controller
  }
};


async function requestUnlinking(token, unlinkDetails) {
  try {
    const streamId = unlinkDetails?.streamId;
    const macAddress = unlinkDetails?.macAddress || utils.read_mac_address();

    if (!streamId || !macAddress) {
      const missing = [];
      if (!streamId) missing.push('streamId');
      if (!macAddress) missing.push('macAddress');
      const err = new Error(`Missing unlink identifiers: ${missing.join(', ')}`);
      err.code = 'MISSING_UNLINK_IDENTIFIERS';
      throw err;
    }

    const json =
    {
      macAddress: macAddress,
      streamId: streamId
    };
    const url = `${buildW1BaseUrl()}/device/unlink`;

    const axiosConfig = {
      headers: {
        Authorization: `Bearer ${token}`
      }
    };

    if (process.env.NODE_ENV === 'production') {
      axiosConfig.httpsAgent = httpsAgent;
    }

    const response = await axios.post(url, json, axiosConfig);

    return response.data?.payload || 'success'; // Device unlinking successful
  } catch (error) {
    console.log("Unlinking request error:" + error);
    throw error; // Send the error to controller
  }
};

module.exports = {
  checkAuthToken,
  ensureValidAccessToken,
  refreshIfExpiringSoon,
  clearLocalLinkState,
  persistDeviceInfo,
  persistToken,
  persistTokenPair,
  getDeviceDetails,
  refreshDeviceMetadataFromHost,
  getStoredDeviceInfo,
  getAccessTokenStatus,
  getRefreshTokenStatus,
  getUnlinkIdentifiers,
  requestLinking,
  requestUnlinking,
  refreshAuthToken,
  buildW1BaseUrl,
};
