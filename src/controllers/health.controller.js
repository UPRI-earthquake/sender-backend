const dns = require('dns').promises;
const net = require('net');
const axios = require('axios');
const https = require('https');
const os = require('os');
const { exec } = require('child_process');
const { promisify } = require('util');
const deviceService = require('../services/device.service');
const { responseCodes } = require('./responseCodes');

const httpsAgent = new https.Agent({ rejectUnauthorized: false });
const execAsync = promisify(exec);
const defaultDiskPath = process.env.RESOURCE_DISK_PATH || '/';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const cpuSampleWindow = Number(process.env.RESOURCE_CPU_SAMPLE_MS || 1000);

async function sampleCpuUsage(sampleWindowMs = cpuSampleWindow) {
  const start = os.cpus();
  if (!start || start.length === 0) {
    return {
      cores: 0,
      usagePercent: null,
      loadAverage: os.loadavg().map((value) => Number(value.toFixed(2))),
    };
  }

  await sleep(sampleWindowMs);
  const end = os.cpus();

  const usageByCore = end.map((cpu, index) => {
    const startTimes = start[index]?.times;
    const endTimes = cpu.times;
    if (!startTimes) {
      return 0;
    }

    const idleDiff = endTimes.idle - startTimes.idle;
    const totalDiff = Object.keys(endTimes).reduce(
      (acc, key) => acc + (endTimes[key] - startTimes[key]),
      0,
    );
    if (totalDiff <= 0) {
      return 0;
    }
    const utilization = 1 - idleDiff / totalDiff;
    return Math.min(Math.max(utilization, 0), 1);
  });

  const avgUsage = usageByCore.reduce((sum, value) => sum + value, 0) / usageByCore.length;
  return {
    cores: end.length,
    usagePercent: Number((avgUsage * 100).toFixed(1)),
    loadAverage: os.loadavg().map((value) => Number(value.toFixed(2))),
  };
}

async function readDiskUsage(path = defaultDiskPath) {
  const { stdout } = await execAsync(`df -kP ${path}`);
  const lines = stdout.trim().split('\n');
  if (lines.length < 2) {
    throw new Error('Unexpected disk usage output');
  }
  const tokens = lines[lines.length - 1].trim().split(/\s+/);
  if (tokens.length < 5) {
    throw new Error('Unable to parse disk usage output');
  }

  const totalKb = Number(tokens[1]);
  const usedKb = Number(tokens[2]);
  const freeKb = Number(tokens[3]);
  const percentToken = tokens[4] || '0%';
  const usedPercent = Number(percentToken.replace('%', '')) || Math.round((usedKb / Math.max(totalKb, 1)) * 100);

  return {
    path,
    totalBytes: totalKb * 1024,
    usedBytes: usedKb * 1024,
    freeBytes: freeKb * 1024,
    usedPercent,
  };
}

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

async function resourcesHealth(req, res) {
  try {
    const [disk, cpu] = await Promise.all([
      readDiskUsage(defaultDiskPath),
      sampleCpuUsage(),
    ]);

    res.status(200).json({
      status: responseCodes.HEALTH_RESOURCES_SUCCESS,
      message: 'Resource usage snapshot',
      payload: {
        disk,
        cpu,
      },
    });
  } catch (error) {
    res.status(500).json({
      status: responseCodes.HEALTH_RESOURCES_ERROR,
      message: 'Unable to read host resource usage',
      error: error.message,
    });
  }
}

module.exports = {
  networkHealth,
  timeHealth,
  resourcesHealth,
};
