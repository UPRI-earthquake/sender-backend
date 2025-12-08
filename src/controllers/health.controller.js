const dns = require('dns').promises;
const net = require('net');
const axios = require('axios');
const https = require('https');
const deviceService = require('../services/device.service');
const { responseCodes } = require('./responseCodes');

const httpsAgent = new https.Agent({ rejectUnauthorized: false });

function buildTarget() {
  const baseUrl = deviceService.buildW1BaseUrl();
  const parsed = new URL(baseUrl.startsWith('http') ? baseUrl : `https://${baseUrl}`);
  const port = parsed.port || (parsed.protocol === 'https:' ? 443 : 80);

  return {
    baseUrl: `${parsed.protocol}//${parsed.host}${parsed.pathname || ''}`,
    hostname: parsed.hostname,
    port,
    protocol: parsed.protocol,
  };
}

async function networkHealth(req, res) {
  const target = buildTarget();
  const responsePayload = {
    target,
    dns: { ok: false },
    tcp: { ok: false },
    https: { ok: false },
  };

  try {
    const lookup = await dns.lookup(target.hostname);
    responsePayload.dns = { ok: true, address: lookup.address };
  } catch (error) {
    responsePayload.dns = { ok: false, error: error.message };
  }

  if (responsePayload.dns.ok) {
    await new Promise((resolve) => {
      const socket = net.createConnection(target.port, target.hostname, () => {
        responsePayload.tcp = { ok: true };
        socket.destroy();
        resolve();
      });

      socket.setTimeout(5000);
      socket.on('error', (error) => {
        responsePayload.tcp = { ok: false, error: error.message };
        resolve();
      });
      socket.on('timeout', () => {
        responsePayload.tcp = { ok: false, error: 'Connection timed out' };
        socket.destroy();
        resolve();
      });
    });
  }

  try {
    const healthUrl = target.baseUrl;
    const resp = await axios.head(healthUrl, { timeout: 5000, httpsAgent, validateStatus: () => true });
    responsePayload.https = { ok: true, status: resp.status };
  } catch (error) {
    responsePayload.https = { ok: false, error: error.message };
  }

  res.status(200).json({
    status: responseCodes.HEALTH_NETWORK_SUCCESS,
    message: 'Network health check complete',
    payload: responsePayload,
  });
}

async function timeHealth(req, res) {
  const target = buildTarget();
  try {
    const start = Date.now();
    const resp = await axios.head(target.baseUrl, { timeout: 5000, httpsAgent, validateStatus: () => true });
    const end = Date.now();
    const serverDate = resp.headers?.date ? new Date(resp.headers.date).getTime() : null;
    const roundTripMs = end - start;
    const adjustedLocal = start + Math.round(roundTripMs / 2);
    const offsetMs = serverDate ? serverDate - adjustedLocal : null;

    res.status(200).json({
      status: responseCodes.HEALTH_TIME_SUCCESS,
      message: 'Time synchronization check complete',
      payload: {
        target,
        serverDate,
        offsetMs,
        roundTripMs,
      }
    });
  } catch (error) {
    res.status(500).json({
      status: responseCodes.HEALTH_TIME_ERROR,
      message: 'Time synchronization check failed',
      error: error.message,
    });
  }
}

module.exports = {
  networkHealth,
  timeHealth,
};
