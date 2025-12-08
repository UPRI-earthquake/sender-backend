const fs = require('fs');
const axios = require('axios');
const https = require('https');
const jwt = require('jsonwebtoken');
const httpsAgent = new https.Agent({ rejectUnauthorized: false });
const utils = require('./utils');

const tokenPath = `${process.env.LOCALDBS_DIRECTORY}/token.json`;
const deviceInfoPath = `${process.env.LOCALDBS_DIRECTORY}/deviceInfo.json`;
const serversPath = `${process.env.LOCALDBS_DIRECTORY}/servers.json`;
const credentialsPath = `${process.env.LOCALDBS_DIRECTORY}/linkCredentials.json`;

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
  if (rawData.deviceInfo) {
    return { ...defaultDeviceInfo, ...rawData.deviceInfo };
  }
  return { ...defaultDeviceInfo, ...rawData };
}

async function persistDeviceInfo(deviceInfo) {
  const normalized = normalizeDeviceInfo(deviceInfo);
  await writeJsonFile(deviceInfoPath, normalized);
  return normalized;
}

async function persistToken(accessToken) {
  const tokenInfo = { accessToken: accessToken || null };
  const decoded = decodeToken(accessToken);
  if (decoded?.exp) {
    tokenInfo.expiresAt = decoded.exp;
  }
  await writeJsonFile(tokenPath, tokenInfo);
  return tokenInfo;
}

async function persistCredentials(credentials) {
  await writeJsonFile(credentialsPath, credentials);
  return credentials;
}

function buildW1BaseUrl() {
  return (process.env.NODE_ENV === 'production')
    ? `https://${process.env.W1_PROD_IP}`
    : `http://${process.env.W1_DEV_IP}:${process.env.W1_DEV_PORT}`;
}

// Function for checking if a jwt access token is already saved 
async function checkAuthToken() {
  const data = await readJsonFile(tokenPath, { accessToken: null, role: "sensor" });
  if (!data?.accessToken) {
    throw new Error('No stored access token');
  }
  return data.accessToken;
}

async function ensureValidAccessToken() {
  const tokenData = await readJsonFile(tokenPath, { accessToken: null });
  if (tokenData?.accessToken) {
    if (!isTokenExpiring(tokenData.accessToken)) {
      return tokenData.accessToken;
    }

    // If we are close to expiry but lack credentials, keep using the token until it fully expires.
    const credentials = await readJsonFile(credentialsPath, null);
    const decoded = decodeToken(tokenData.accessToken);
    const nowSeconds = Math.floor(Date.now() / 1000);
    if ((!credentials || !credentials.username || !credentials.password) && decoded?.exp && decoded.exp > nowSeconds) {
      return tokenData.accessToken;
    }
  }

  return refreshAuthToken();
}

async function refreshAuthToken() {
  const credentials = await readJsonFile(credentialsPath, null);
  if (!credentials || !credentials.username || !credentials.password) {
    throw new Error('No stored credentials available to refresh token');
  }

  const payload = await requestLinking({
    username: credentials.username,
    password: credentials.password,
    longitude: credentials.longitude,
    latitude: credentials.latitude,
    elevation: credentials.elevation,
    forceRelink: true,
  });

  await persistToken(payload.accessToken);
  await persistDeviceInfo(payload.deviceInfo);

  return payload.accessToken;
}

async function clearLocalLinkState() {
  await persistToken(null);
  await persistDeviceInfo(defaultDeviceInfo);
  await persistCredentials({
    username: null,
    password: null,
    longitude: null,
    latitude: null,
    elevation: null,
    forceRelink: true,
  });
  await writeJsonFile(serversPath, []);
}

async function getDeviceDetails() {
  const hostConfig = utils.getHostDeviceConfig();
  const storedInfo = normalizeDeviceInfo(await readJsonFile(deviceInfoPath, defaultDeviceInfo));
  const token = await readJsonFile(tokenPath, { accessToken: null });

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
    linked: Boolean(storedInfo.streamId && token?.accessToken)
  };
}

// Function for adding the device to db in W1 and linking it to the user input account details
async function requestLinking(userInput) {
  try {
    const streamId = utils.generate_streamId();
    const macAddress = utils.read_mac_address();

    const json =
    {
      username: userInput.username,
      password: userInput.password,
      role: 'sensor',
      longitude: userInput.longitude,
      latitude: userInput.latitude,
      elevation: userInput.elevation,
      macAddress: macAddress,
      streamId: streamId,
      forceRelink: Boolean(userInput.forceRelink),
    };
    const url = `${buildW1BaseUrl()}/device/link`;

    const response = await axios.post(url, json, {
      httpsAgent,
    })

    return response.data.payload; // The device information obtained from the response
  } catch (error) {
    console.log("requestLinking error:" + error);
    throw error; // Send the error to controller
  }
};


async function requestUnlinking(token) {
  try {
    const streamId = utils.generate_streamId();
    const macAddress = utils.read_mac_address();

    const json =
    {
      macAddress: macAddress,
      streamId: streamId
    };
    const url = `${buildW1BaseUrl()}/device/unlink`;

    const response = (process.env.NODE_ENV === 'production')
      ? await axios.post(url, json, {
        httpsAgent,
        headers: {
          Authorization: `Bearer ${token}`
        }
      })
      : await axios.post(url, json, {
        headers: {
          Authorization: `Bearer ${token}`
        }
      })

    return 'success'; // Device unlinking successful
  } catch (error) {
    console.log("Unlinking request error:" + error);
    throw error; // Send the error to controller
  }
};

module.exports = {
  checkAuthToken,
  ensureValidAccessToken,
  clearLocalLinkState,
  persistDeviceInfo,
  persistCredentials,
  persistToken,
  getDeviceDetails,
  requestLinking,
  requestUnlinking,
  refreshAuthToken,
  buildW1BaseUrl,
};
