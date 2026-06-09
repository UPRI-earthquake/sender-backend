const fs = require('fs').promises;
const path = require('path');
const Joi = require('joi');
const serversService = require('../services/servers.service')
const streamUtils = require('./stream.utils')
const deviceService = require('../services/device.service');
const { responseCodes, responseMessages } = require('./responseCodes')

const localDbDir = () => process.env.LOCALDBS_DIRECTORY || './localDBs';
const serversFilePath = () => path.join(localDbDir(), 'servers.json');
const DEFAULT_RINGSERVER_USERNAME_FALLBACK = 'UP-Diliman';
const DEFAULT_RINGSERVER_URL_FALLBACK = 'earthquake.up.edu.ph:16000';

function parseBooleanEnv(value, defaultValue = false) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return defaultValue;
  }
  const normalized = String(value).trim().toLowerCase();
  return normalized === '1'
    || normalized === 'true'
    || normalized === 'yes'
    || normalized === 'on';
}

function normalizeServerUrl(url) {
  return String(url || '')
    .trim()
    .replace(/^https?:\/\//i, '')
    .replace(/\/+$/g, '')
    .toLowerCase();
}

function getDefaultRingserverConfig() {
  const configuredUsername = String(
    process.env.DEFAULT_RINGSERVER_USERNAME || DEFAULT_RINGSERVER_USERNAME_FALLBACK,
  ).trim();
  const configuredUrl = String(process.env.DEFAULT_RINGSERVER_URL || '').trim();
  return {
    username: configuredUsername || DEFAULT_RINGSERVER_USERNAME_FALLBACK,
    url: configuredUrl,
  };
}

function autoAddDefaultRingserverEnabled() {
  const defaultEnabled = process.env.NODE_ENV === 'test' ? false : true;
  return parseBooleanEnv(process.env.AUTO_ADD_DEFAULT_RINGSERVER_ON_LINK, defaultEnabled);
}

function autoEnsureDefaultRingserverOnStartupEnabled() {
  const defaultEnabled = process.env.NODE_ENV === 'test' ? false : true;
  return parseBooleanEnv(process.env.AUTO_ADD_DEFAULT_RINGSERVER_ON_STARTUP, defaultEnabled);
}

function getProtectedRingserverConfig() {
  const defaultConfig = getDefaultRingserverConfig();
  return {
    username: String(process.env.PROTECTED_RINGSERVER_USERNAME || defaultConfig.username || '').trim(),
    url: String(process.env.PROTECTED_RINGSERVER_URL || defaultConfig.url || '').trim(),
  };
}

function isProtectedRingserver(entry = {}) {
  const { username, url } = getProtectedRingserverConfig();
  const entryUsername = String(entry.institutionName || '').trim();
  if (username && entryUsername.toLowerCase() === username.toLowerCase()) {
    return true;
  }
  if (url && normalizeServerUrl(entry.url) === normalizeServerUrl(url)) {
    return true;
  }
  return false;
}

async function resolveDefaultRingserverTarget() {
  const { username: defaultUsername, url: defaultUrl } = getDefaultRingserverConfig();
  if (defaultUrl) {
    return {
      institutionName: defaultUsername,
      url: defaultUrl,
    };
  }

  const ringserverHosts = await serversService.requestRingserverHostsList();
  if (!Array.isArray(ringserverHosts) || ringserverHosts.length === 0) {
    return null;
  }

  const matchedHost = ringserverHosts.find((host) => {
    const candidate = String(host?.username || '').trim();
    return candidate.toLowerCase() === defaultUsername.toLowerCase();
  });

  if (!matchedHost) {
    if (defaultUsername.toLowerCase() === DEFAULT_RINGSERVER_USERNAME_FALLBACK.toLowerCase()) {
      return {
        institutionName: defaultUsername,
        url: DEFAULT_RINGSERVER_URL_FALLBACK,
      };
    }
    return null;
  }

  const ringserverUrl = String(matchedHost.ringserverUrl || '').trim();
  const ringserverPort = String(matchedHost.ringserverPort || '').trim();
  if (!ringserverUrl || !ringserverPort) {
    return null;
  }

  return {
    institutionName: String(matchedHost.username || defaultUsername),
    url: `${ringserverUrl}:${ringserverPort}`,
  };
}

async function ensureDefaultRingserver() {
  const target = await resolveDefaultRingserverTarget();
  if (!target?.url) {
    return { attempted: true, added: false, reason: 'default-ringserver-unresolved' };
  }

  const existingServers = await readLocalServersList();
  const targetUrlNormalized = normalizeServerUrl(target.url);
  const duplicate = existingServers.find((item) => normalizeServerUrl(item?.url) === targetUrlNormalized);
  if (duplicate) {
    return {
      attempted: true,
      added: false,
      reason: 'already-exists',
      server: duplicate,
    };
  }

  const newServer = {
    institutionName: target.institutionName,
    url: target.url,
  };

  existingServers.push(newServer);
  await writeLocalServersList(existingServers);
  await streamUtils.addNewStream(newServer.url, newServer.institutionName);
  await streamUtils.spawnSlink2dali(newServer.url);

  return {
    attempted: true,
    added: true,
    reason: 'added',
    server: newServer,
  };
}

async function ensureDefaultRingserverAfterLink() {
  if (!autoAddDefaultRingserverEnabled()) {
    return { attempted: false, added: false, reason: 'auto-add-disabled' };
  }

  return ensureDefaultRingserver();
}

async function ensureDefaultRingserverOnStartup() {
  if (!autoEnsureDefaultRingserverOnStartupEnabled()) {
    return { attempted: false, added: false, reason: 'startup-auto-add-disabled' };
  }

  try {
    await deviceService.ensureValidAccessToken({ skipAlertCredentialSync: true });
  } catch (error) {
    return {
      attempted: false,
      added: false,
      reason: error?.code === 'RELINK_REQUIRED' ? 'device-not-linked' : 'token-check-failed',
      errorMessage: error?.message || String(error),
    };
  }

  return ensureDefaultRingserver();
}

async function readLocalServersList() {
  try {
    const jsonString = await fs.readFile(serversFilePath(), 'utf-8');
    const parsed = JSON.parse(jsonString);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return [];
    }
    throw error;
  }
}

async function writeLocalServersList(serversList) {
  const filePath = serversFilePath();
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(serversList));
}

// Function for getting the list of valid ringserver hosts registered in W1
async function getRingserverHosts(req, res) {
  try {
    const data = await serversService.requestRingserverHostsList();
    
    res.status(200).json({
      status: responseCodes.GET_SERVERS_LIST_SUCCESS,
      message: 'Get List of Ringserver Hosts Success', 
      payload: data });
  } catch (err) {
    console.error(`Error getRingserverHosts(): ${err}`);
    res.status(500).json({ 
      status: responseCodes.GET_SERVERS_LIST_SUCCESS,
      message: 'Error getting ringserver hosts' });
  }
}


// Middleware function that checks if the device is already linked to an account
async function linkingStatusCheck(req, res, next) {
  try {
    await deviceService.ensureValidAccessToken();
  } catch (error) {
    const relinkRequired = error?.code === 'RELINK_REQUIRED';
    return res.status(409).json({ 
      status: relinkRequired
        ? responseCodes.DEVICE_RELINK_REQUIRED
        : responseCodes.ADD_SERVER_DEVICE_NOT_YET_LINKED,
      message: relinkRequired
        ? (error.message || 'Device credentials expired. Relink the device before adding a ringserver URL.')
        : 'Link your device first before adding a ringserver url',
    });
  }

  next(); // Proceed to the next middleware/route handler
}

// Function for adding server to json array, adding server to streams object dictionary, and spawning childprocess
async function addServer(req, res) {
  // No validation schema since this input is coming directly from W1, not a user input

  try {
    const existingServers = await readLocalServersList();

    const duplicate = existingServers.find((item) => item.url === req.body.url);
    if (duplicate) {
      return res.status(401).json({ 
        status: responseCodes.ADD_SERVER_DUPLICATE,
        message: "Server URL already saved" });
    }

    const newServer = {
      institutionName: req.body.institutionName,
      url: req.body.url
    };

    existingServers.push(newServer);
    await writeLocalServersList(existingServers); // Add the input server to the array of servers in a json file (servers.json)

    await streamUtils.addNewStream(req.body.url, req.body.institutionName); // Adds the newly added server to streams object dictionary
    await streamUtils.spawnSlink2dali(req.body.url); // ASpawns slink2dali childprocess that starts streaming to the specified ringserver url

    console.log("Server added successfully");
    return res.status(200).json({ 
      status: responseCodes.ADD_SERVER_SUCCESS, 
      message: "Server added successfully" });
  } catch (e) {
    console.log(`Error: ${e}`);
    return res.status(500).json({ 
      status: responseCodes.ADD_SERVER_ERROR,
      message: "Error occurred in adding server" });
  }
}

// Function for removing a server from local store and streamsObject
async function removeServer(req, res) {
  const url = req.body?.url;
  if (!url) {
    return res.status(400).json({
      status: responseCodes.REMOVE_SERVER_ERROR,
      message: 'Missing server url',
    });
  }

  try {
    const { removedUrls } = await streamUtils.reconcileStreamsWithFile();
    const existingServers = await readLocalServersList();

    const index = existingServers.findIndex((item) => item.url === url);
    if (index === -1) {
      if (removedUrls.includes(url)) {
        return res.status(200).json({
          status: responseCodes.REMOVE_SERVER_SUCCESS,
          message: 'Server removed successfully',
        });
      }
      return res.status(404).json({
        status: responseCodes.REMOVE_SERVER_NOT_FOUND,
        message: 'Server URL not found',
      });
    }

    const targetServer = existingServers[index] || {};
    if (isProtectedRingserver(targetServer)) {
      return res.status(409).json({
        status: responseCodes.REMOVE_SERVER_ERROR,
        message: 'Protected default ringserver cannot be removed',
      });
    }

    // Attempt remote cleanup on the associated brgy account
    const brgyUsername = targetServer.institutionName;
    const { streamId } = await deviceService.getStoredDeviceInfo();
    if (brgyUsername && streamId) {
      try {
        const token = await deviceService.ensureValidAccessToken();
        await serversService.removeDeviceFromBrgyAccount(token, brgyUsername, streamId);
      } catch (error) {
        console.log(`Error removing device from brgy account ${brgyUsername}: ${error}`);
        if (error?.code === 'RELINK_REQUIRED') {
          return res.status(409).json({
            status: responseCodes.DEVICE_RELINK_REQUIRED,
            message: error.message || responseMessages.DEVICE_RELINK_REQUIRED,
          });
        }
        if (error?.response) {
          return res.status(error.response.status).json({
            status: responseCodes.REMOVE_SERVER_ERROR,
            message: error.response?.data?.message || 'Error removing device from brgy account',
          });
        }
        return res.status(500).json({
          status: responseCodes.REMOVE_SERVER_ERROR,
          message: 'Error removing device from brgy account',
        });
      }
    }

    existingServers.splice(index, 1);
    await writeLocalServersList(existingServers);
    await streamUtils.removeStream(url);

    return res.status(200).json({
      status: responseCodes.REMOVE_SERVER_SUCCESS,
      message: 'Server removed successfully',
    });
  } catch (error) {
    console.log(`Error removing server: ${error}`);
    return res.status(500).json({
      status: responseCodes.REMOVE_SERVER_ERROR,
      message: 'Error occurred in removing server',
    });
  }
}

module.exports = {
  getRingserverHosts,
  addServer,
  removeServer,
  linkingStatusCheck,
  ensureDefaultRingserverAfterLink,
  ensureDefaultRingserverOnStartup,
};
