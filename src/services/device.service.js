const fs = require('fs');
const path = require('path');
const axios = require('axios');
const https = require('https');
const jwt = require('jsonwebtoken');
const utils = require('./utils');
const alertCredentialService = require('./alertCredential.service');

const localDbPath = (fileName) => `${process.env.LOCALDBS_DIRECTORY || './localDBs'}/${fileName}`;
const tokenPath = () => localDbPath('token.json');
const deviceInfoPath = () => localDbPath('deviceInfo.json');
const serversPath = () => localDbPath('servers.json');

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
const deviceStatusPath = '/device/status';
const alertCredentialPath = '/device/alert-credential';
const allowInsecureW1Tls = String(process.env.W1_ALLOW_INSECURE_TLS || 'true').trim().toLowerCase() === 'true';
const httpsAgent = new https.Agent({ rejectUnauthorized: !allowInsecureW1Tls });
const defaultProdW1Host = 'earthquake.up.edu.ph/api';

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

function unwrapAlertCredential(payload) {
  if (!payload || typeof payload !== 'object') {
    return null;
  }
  if (payload.rshakeAlertCredential && typeof payload.rshakeAlertCredential === 'object') {
    return payload.rshakeAlertCredential;
  }
  return null;
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
  const dir = path.dirname(filePath);
  const baseName = path.basename(filePath);
  const tmpPath = path.join(dir, `.${baseName}.${process.pid}.${Date.now()}.tmp`);
  await fs.promises.mkdir(dir, { recursive: true });
  await fs.promises.writeFile(tmpPath, JSON.stringify(data));
  await fs.promises.rename(tmpPath, filePath);
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

function buildStreamIdFromFields(network, station) {
  if (!network || !station) {
    return null;
  }
  return `${network}_${station}_.*/MSEED`;
}

function normalizeIdentityCandidate(candidate = {}) {
  const network = typeof candidate.network === 'string' ? candidate.network.trim() : candidate.network;
  const station = typeof candidate.station === 'string' ? candidate.station.trim() : candidate.station;
  const streamId = typeof candidate.streamId === 'string' ? candidate.streamId.trim() : candidate.streamId;

  return {
    source: candidate.source || 'unknown',
    network: network || null,
    station: station || null,
    streamId: streamId || null,
  };
}

function buildIdentityCandidates(storedInfo = {}, hostConfig = {}) {
  const candidates = [
    normalizeIdentityCandidate({
      source: 'host',
      network: hostConfig?.network,
      station: hostConfig?.station,
      streamId: hostConfig?.streamId || buildStreamIdFromFields(hostConfig?.network, hostConfig?.station),
    }),
    normalizeIdentityCandidate({
      source: 'stored',
      network: storedInfo?.network,
      station: storedInfo?.station,
      streamId: storedInfo?.streamId || buildStreamIdFromFields(storedInfo?.network, storedInfo?.station),
    }),
  ].filter((candidate) => candidate.streamId || (candidate.network && candidate.station));

  const seen = new Set();
  return candidates.filter((candidate) => {
    const key = `${candidate.network || ''}|${candidate.station || ''}|${candidate.streamId || ''}`;
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

async function resolveRemoteLinkState(identityCandidates = []) {
  for (const candidate of identityCandidates) {
    if (!candidate?.network || !candidate?.station) {
      continue;
    }

    const { state } = await fetchRemoteLinkState(candidate.network, candidate.station);
    if (state === 'notLinked') {
      continue;
    }
    return state;
  }

  return 'unknown';
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

async function persistAlertCredential(alertCredential) {
  const sharedSecret = String(alertCredential?.sharedSecret || '').trim();
  if (!sharedSecret) {
    return { persisted: false };
  }

  return alertCredentialService.persistAlertSharedSecret(sharedSecret, {
    issuedAt: alertCredential?.issuedAt || '',
  });
}

async function getStoredDeviceInfo() {
  const stored = await readJsonFile(deviceInfoPath(), defaultDeviceInfo);
  return normalizeDeviceInfo(stored);
}

function buildW1BaseUrl() {
  if (process.env.NODE_ENV === 'production') {
    const configuredHost = String(process.env.W1_PROD_IP || '').trim().replace(/^https?:\/\//, '').replace(/\/+$/, '');
    const prodHost = configuredHost || defaultProdW1Host;
    return `https://${prodHost}`;
  }

  return `http://${process.env.W1_DEV_IP}:${process.env.W1_DEV_PORT}`;
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

async function ensureValidAccessToken({ skipAlertCredentialSync = false } = {}) {
  const tokenData = await readJsonFile(tokenPath(), createDefaultTokenInfo());
  if (tokenData?.accessToken) {
    if (!isTokenExpiring(tokenData.accessToken)) {
      return tokenData.accessToken;
    }
  }

  return refreshAuthToken({ skipAlertCredentialSync });
}

async function refreshAuthToken({ skipAlertCredentialSync = false } = {}) {
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

  if (!skipAlertCredentialSync) {
    const issuedCredential = unwrapAlertCredential(payload);
    if (issuedCredential?.sharedSecret) {
      await persistAlertCredential(issuedCredential);
    } else {
      await syncRshakeAlertCredential({
        accessToken: payload.accessToken,
        allowTokenRefresh: false,
      });
    }
  }

  return payload.accessToken;
}

async function refreshIfExpiringSoon() {
  const refreshResult = await refreshIfExpiringSoonWithStatus();
  if (refreshResult.attempted && !refreshResult.success) {
    const err = new Error(refreshResult.errorMessage || 'Proactive token refresh failed');
    if (refreshResult.errorCode) {
      err.code = refreshResult.errorCode;
    }
    if (refreshResult.errorStatus) {
      err.status = refreshResult.errorStatus;
    }
    throw err;
  }
  return refreshResult.accessToken || null;
}

async function refreshIfExpiringSoonWithStatus() {
  const tokenData = await readJsonFile(tokenPath(), createDefaultTokenInfo());
  const [status, refreshStatus] = await Promise.all([
    getAccessTokenStatus(),
    getRefreshTokenStatus(),
  ]);

  // If token missing/invalid/expired, try refresh immediately
  // If token exists but expiring soon per configured leeway, refresh
  const shouldRefresh =
    ['missing', 'invalid', 'corrupted', 'expired'].includes(status.state)
    || (
      status.state === 'valid'
      && typeof status.secondsToExpiry === 'number'
      && status.secondsToExpiry * 1000 <= refreshLeewayMs
    );

  if (!shouldRefresh) {
    return {
      attempted: false,
      success: true,
      reason: 'notDue',
      accessToken: tokenData?.accessToken || null,
      tokenStatusBefore: status,
      refreshTokenStatus: refreshStatus,
    };
  }

  if (['missing', 'invalid', 'expired', 'corrupted'].includes(refreshStatus.state)) {
    return {
      attempted: true,
      success: false,
      reason: 'refreshTokenUnavailable',
      accessToken: tokenData?.accessToken || null,
      tokenStatusBefore: status,
      refreshTokenStatus: refreshStatus,
      errorMessage: refreshStatus?.reason || 'Refresh token unavailable',
      errorCode: 'REFRESH_TOKEN_UNAVAILABLE',
      errorStatus: null,
    };
  }

  try {
    const refreshedAccessToken = await refreshAuthToken();
    const tokenStatusAfter = await getAccessTokenStatus();
    return {
      attempted: true,
      success: true,
      reason: 'refreshed',
      accessToken: refreshedAccessToken,
      tokenStatusBefore: status,
      tokenStatusAfter,
      refreshTokenStatus: refreshStatus,
    };
  } catch (error) {
    return {
      attempted: true,
      success: false,
      reason: 'refreshFailed',
      accessToken: tokenData?.accessToken || null,
      tokenStatusBefore: status,
      refreshTokenStatus: refreshStatus,
      errorMessage: error?.message || String(error),
      errorCode: error?.code || null,
      errorStatus: error?.status || error?.response?.status || error?.meta?.status || null,
    };
  }
}

async function clearLocalLinkState() {
  await persistTokenPair({ accessToken: null, refreshToken: null, deviceInfo: defaultDeviceInfo });
  await writeJsonFile(serversPath(), []);
  await alertCredentialService.clearAlertSharedSecret();
}

async function getDeviceDetails() {
  const hostConfig = normalizeHostConfig(utils.getHostDeviceConfig());
  const storedInfo = await getStoredDeviceInfo();
  const token = await readJsonFile(tokenPath(), createDefaultTokenInfo());
  const tokenStatus = await getAccessTokenStatus();
  const refreshTokenStatus = await getRefreshTokenStatus();
  const identityCandidates = buildIdentityCandidates(storedInfo, hostConfig);
  const preferredIdentity = identityCandidates[0] || {};

  const mergedDevice = {
    network: preferredIdentity.network || storedInfo.network || hostConfig?.network || null,
    station: preferredIdentity.station || storedInfo.station || hostConfig?.station || null,
    longitude: storedInfo.longitude ?? hostConfig.longitude,
    latitude: storedInfo.latitude ?? hostConfig.latitude,
    elevation: storedInfo.elevation ?? hostConfig.elevation,
    streamId: preferredIdentity.streamId || storedInfo.streamId || hostConfig?.streamId || null,
  };

  let linkState = 'unknown';
  try {
    linkState = await resolveRemoteLinkState(identityCandidates);
  } catch (error) {
    console.log(`Remote link state lookup failed: ${error}`);
  }

  return {
    deviceInfo: mergedDevice,
    hostConfig,
    linked: Boolean(storedInfo.streamId && token?.accessToken),
    tokenStatus,
    refreshTokenStatus,
    linkState,
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

  const streamIdFromStoredFields = buildStreamIdFromFields(storedInfo.network, storedInfo.station);

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

async function requestAlertCredential(accessToken, identifiers = {}) {
  const url = `${buildW1BaseUrl()}${alertCredentialPath}`;
  const axiosConfig = {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
    timeout: Number(process.env.RSHAKE_ALERT_CREDENTIAL_TIMEOUT_MS || 5000),
  };

  if (process.env.NODE_ENV === 'production') {
    axiosConfig.httpsAgent = httpsAgent;
  }

  const response = await axios.post(url, identifiers, axiosConfig);
  const payload = extractPayload(response.data);
  if (!payload || typeof payload !== 'object') {
    throw new Error('W1 alert credential response missing payload');
  }
  return payload;
}

async function syncRshakeAlertCredential({ accessToken = '', allowTokenRefresh = false } = {}) {
  let resolvedAccessToken = String(accessToken || '').trim();
  if (!resolvedAccessToken && allowTokenRefresh) {
    resolvedAccessToken = await ensureValidAccessToken({ skipAlertCredentialSync: true });
  }
  if (!resolvedAccessToken) {
    return { str: 'skipped', reason: 'missingAccessToken' };
  }

  const identifiers = await getUnlinkIdentifiers();
  if (!identifiers.streamId && !identifiers.macAddress && !(identifiers.network && identifiers.station)) {
    return { str: 'skipped', reason: 'missingDeviceIdentifiers' };
  }

  const payload = await requestAlertCredential(resolvedAccessToken, {
    macAddress: identifiers.macAddress || undefined,
    streamId: identifiers.streamId || undefined,
    network: identifiers.network || undefined,
    station: identifiers.station || undefined,
  });

  if (!payload.sharedSecret) {
    return { str: 'skipped', reason: 'missingSharedSecret' };
  }

  await persistAlertCredential(payload);
  if (payload.deviceInfo) {
    await persistDeviceInfo(payload.deviceInfo, { overwrite: false });
  }

  return {
    str: 'success',
    issuedAt: payload.issuedAt || null,
  };
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
	    });

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

async function requestLinkReset(token, resetDetails) {
  try {
    const streamId = resetDetails?.streamId;
    const macAddress = resetDetails?.macAddress || utils.read_mac_address();

    if (!streamId || !macAddress) {
      const missing = [];
      if (!streamId) missing.push('streamId');
      if (!macAddress) missing.push('macAddress');
      const err = new Error(`Missing reset identifiers: ${missing.join(', ')}`);
      err.code = 'MISSING_RESET_IDENTIFIERS';
      throw err;
    }

    const json = {
      macAddress,
      streamId,
    };
    const url = `${buildW1BaseUrl()}/device/reset-link`;

    const axiosConfig = { headers: {} };
    if (token) {
      axiosConfig.headers.Authorization = `Bearer ${token}`;
    }

    if (process.env.NODE_ENV === 'production') {
      axiosConfig.httpsAgent = httpsAgent;
    }

    const response = await axios.post(url, json, axiosConfig);

    return response.data?.payload || 'success';
  } catch (error) {
    console.log(`Link reset request error: ${error}`);
    throw error;
  }
};

module.exports = {
  checkAuthToken,
  ensureValidAccessToken,
  refreshIfExpiringSoon,
  refreshIfExpiringSoonWithStatus,
  clearLocalLinkState,
  persistAlertCredential,
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
  requestLinkReset,
  syncRshakeAlertCredential,
  refreshAuthToken,
  buildW1BaseUrl,
  fetchRemoteLinkState,
};

async function fetchRemoteLinkState(network, station) {
  if (!network || !station) {
    return { state: 'unknown' };
  }

  const url = `${buildW1BaseUrl()}${deviceStatusPath}?network=${encodeURIComponent(network)}&station=${encodeURIComponent(station)}`;
  const axiosConfig = {};
  if (process.env.NODE_ENV === 'production') {
    axiosConfig.httpsAgent = httpsAgent;
  }

  try {
    const response = await axios.get(url, axiosConfig);
    const activity = response?.data?.payload?.activity || response?.data?.payload?.status || null;
    if (activity === 'unlinked') {
      return { state: 'unlinked' };
    }
    return { state: 'linked' };
  } catch (error) {
    if (error?.response && error.response.status === 400) {
      return { state: 'notLinked' };
    }
    return { state: 'unknown' };
  }
}
