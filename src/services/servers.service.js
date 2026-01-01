const axios = require('axios');
const fs = require('fs').promises;
const path = require('path');
const { buildW1BaseUrl } = require('./device.service');

const localDbPath = (fileName) => path.join(process.env.LOCALDBS_DIRECTORY || './localDBs', fileName);

async function requestRingserverHostsList() {
  try {
    const url = (process.env.NODE_ENV === 'production')
      ? 'https://' + process.env.W1_PROD_IP + '/accounts/ringserver-hosts'
      : 'http://' + process.env.W1_DEV_IP + ':' + process.env.W1_DEV_PORT + '/accounts/ringserver-hosts';

    const response = await axios.get(url);

    return response.data.payload; // Ringserver hosts list obtained from the response
  } catch (error) {
    console.log("requestRingserverHostsList() error:" + error);
    throw error; // Send the error to controller
  }
};

async function readSavedServers() {
  try {
    const contents = await fs.readFile(localDbPath('servers.json'), 'utf-8');
    const parsed = JSON.parse(contents);
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed;
  } catch (error) {
    console.log(`readSavedServers() error: ${error}`);
    return [];
  }
}

async function removeDeviceFromBrgyAccount(token, brgyUsername, streamId) {
  if (!token) {
    const err = new Error('Missing access token for device removal');
    err.code = 'MISSING_TOKEN';
    throw err;
  }
  if (!brgyUsername || !streamId) {
    const err = new Error('Missing brgyUsername or streamId for device removal');
    err.code = 'MISSING_PARAMS';
    throw err;
  }

  const url = `${buildW1BaseUrl()}/accounts/brgy/remove-device`;
  try {
    return await axios.post(
      url,
      { brgyUsername, streamId },
      { headers: { Authorization: `Bearer ${token}` } },
    );
  } catch (error) {
    console.log(`removeDeviceFromBrgyAccount() error: ${error}`);
    if (error?.response) {
      const status = error.response.status;
      // Treat not-found/invalid/role errors as non-fatal so unlink can proceed
      if ([400, 404].includes(status)) {
        return null;
      }
    }
    throw error;
  }
}

async function removeDeviceFromAllBrgyAccounts(token, streamId) {
  const servers = await readSavedServers();
  if (!servers.length) return;

  // Deduplicate by institutionName to avoid repeat calls
  const seen = new Set();
  for (const server of servers) {
    const brgyUsername = server?.institutionName;
    if (!brgyUsername || seen.has(brgyUsername)) {
      continue;
    }
    seen.add(brgyUsername);
    try {
      await removeDeviceFromBrgyAccount(token, brgyUsername, streamId);
    } catch (error) {
      // Best-effort: continue other brgy accounts while logging
      console.log(`removeDeviceFromAllBrgyAccounts() error for ${brgyUsername}: ${error}`);
    }
  }
}

module.exports = {
  requestRingserverHostsList,
  removeDeviceFromBrgyAccount,
  removeDeviceFromAllBrgyAccounts,
};
