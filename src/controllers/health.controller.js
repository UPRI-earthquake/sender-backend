const dns = require('dns').promises;
const net = require('net');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const Sntp = require('@hapi/sntp');
const https = require('https');
const os = require('os');
const { execFile } = require('child_process');
const { promisify } = require('util');
const deviceService = require('../services/device.service');
const { responseCodes } = require('./responseCodes');

const httpsAgent = new https.Agent({ rejectUnauthorized: false });
const execFileAsync = promisify(execFile);
const defaultDiskPath = process.env.RESOURCE_DISK_PATH || '/';
const ntpPort = Number(process.env.NTP_SERVER_PORT || 123);
const ntpTimeoutMs = Number(process.env.NTP_REQUEST_TIMEOUT_MS || 2000);
const primaryNtpHost = (process.env.NTP_SERVER_HOST || process.env.NTP_SERVER || '').trim();
const ntpHostListRaw = process.env.NTP_SERVER_HOSTS || '';
const defaultNtpHost = 'time.google.com';
const defaultRingserverPort = Number(process.env.RINGSERVER_DEFAULT_PORT || 18000);
const ringserverTcpTimeoutMs = Number(process.env.RINGSERVER_TCP_TIMEOUT_MS || 5000);
const localDbDir = () => process.env.LOCALDBS_DIRECTORY || './localDBs';
const serversListPath = () => path.join(localDbDir(), 'servers.json');
const fsp = fs.promises;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const cpuSampleWindow = Number(process.env.RESOURCE_CPU_SAMPLE_MS || 1000);
const cpuSampleCacheMs = Number(process.env.RESOURCE_CPU_CACHE_MS || cpuSampleWindow);

let cachedCpuSample = null;
let cachedCpuSampleAt = 0;
let cachedCpuSamplePromise = null;

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

async function getCpuUsageSnapshot(sampleWindowMs = cpuSampleWindow) {
  const cacheable = sampleWindowMs === cpuSampleWindow;
  const now = Date.now();
  if (cacheable && cachedCpuSample && now - cachedCpuSampleAt <= cpuSampleCacheMs) {
    return cachedCpuSample;
  }
  if (cacheable && cachedCpuSamplePromise) {
    return cachedCpuSamplePromise;
  }

  const sampler = sampleCpuUsage(sampleWindowMs).then((result) => {
    if (cacheable) {
      cachedCpuSample = result;
      cachedCpuSampleAt = Date.now();
    }
    return result;
  });

  if (!cacheable) {
    return sampler;
  }

  cachedCpuSamplePromise = sampler;
  try {
    return await sampler;
  } finally {
    cachedCpuSamplePromise = null;
  }
}

async function readDiskUsage(diskPath = defaultDiskPath) {
  // Avoid shell interpolation (diskPath can come from env and may contain spaces).
  const { stdout } = await execFileAsync('df', ['-kP', '--', diskPath]);
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
    path: diskPath,
    totalBytes: totalKb * 1024,
    usedBytes: usedKb * 1024,
    freeBytes: freeKb * 1024,
    usedPercent,
  };
}

let cachedTarget = null;
let cachedTargetBaseUrl = null;

function buildTarget() {
  const baseUrl = deviceService.buildW1BaseUrl();
  if (cachedTarget && cachedTargetBaseUrl === baseUrl) {
    return cachedTarget;
  }
  const parsed = new URL(baseUrl.startsWith('http') ? baseUrl : `https://${baseUrl}`);
  const parsedPort = parsed.port ? Number(parsed.port) : null;
  const port = Number.isFinite(parsedPort) && parsedPort > 0
    ? parsedPort
    : (parsed.protocol === 'https:' ? 443 : 80);

  cachedTargetBaseUrl = baseUrl;
  cachedTarget = {
    baseUrl: `${parsed.protocol}//${parsed.host}${parsed.pathname || ''}`,
    hostname: parsed.hostname,
    port,
    protocol: parsed.protocol,
  };
  return cachedTarget;
}

function hasScheme(value = '') {
  return /^[a-zA-Z][\w+.-]*:\/\//.test(value);
}

function parseHostPortFallback(value) {
  if (!value || typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  if (trimmed.startsWith('[')) {
    const match = trimmed.match(/^\[([^\]]+)\](?::(\d+))?$/);
    if (match) {
      const portValue = match[2] ? Number(match[2]) : null;
      return {
        hostname: match[1],
        port: Number.isFinite(portValue) && portValue > 0 ? portValue : null,
      };
    }
    return null;
  }

  const portMatch = trimmed.match(/:(\d+)$/);
  if (portMatch) {
    const portValue = Number(portMatch[1]);
    const hostname = trimmed.slice(0, trimmed.length - portMatch[0].length);
    if (hostname) {
      if (hostname.includes(':') && net.isIP(hostname) !== 6) {
        return null;
      }
      return {
        hostname,
        port: Number.isFinite(portValue) && portValue > 0 ? portValue : null,
      };
    }
  }

  if (trimmed.includes(':') && net.isIP(trimmed) !== 6) {
    return null;
  }

  return { hostname: trimmed, port: null };
}

function parseRingserverHost(urlText) {
  if (!urlText || typeof urlText !== 'string') {
    return null;
  }
  const trimmed = urlText.trim();
  if (!trimmed) {
    return null;
  }

  const normalized = hasScheme(trimmed) ? trimmed : `tcp://${trimmed}`;
  try {
    const parsed = new URL(normalized);
    const hostname = parsed.hostname || parsed.host;
    if (!hostname) {
      return null;
    }
    const parsedPort = parsed.port ? Number(parsed.port) : null;
    return {
      hostname,
      port: Number.isFinite(parsedPort) && parsedPort > 0 ? parsedPort : defaultRingserverPort,
      protocol: (parsed.protocol || '').replace(/:$/, '') || 'tcp',
    };
  } catch (error) {
    const fallback = parseHostPortFallback(trimmed);
    if (!fallback || !fallback.hostname) {
      return null;
    }
    return {
      hostname: fallback.hostname,
      port: Number.isFinite(fallback.port) && fallback.port > 0 ? fallback.port : defaultRingserverPort,
      protocol: 'tcp',
    };
  }
}

function normalizeRingserverEntry(rawEntry, index) {
  if (!rawEntry) {
    return null;
  }

  let url = null;
  let label = null;

  if (typeof rawEntry === 'string') {
    url = rawEntry.trim();
  } else if (typeof rawEntry === 'object') {
    url = typeof rawEntry.url === 'string' ? rawEntry.url.trim() : null;
    label = rawEntry.institutionName || rawEntry.hostName || rawEntry.username || rawEntry.label || null;
  }

  if (!url) {
    return null;
  }

  const target = parseRingserverHost(url);
  if (!target) {
    return null;
  }

  const hostnameLabel = target.hostname
    ? `${target.hostname}${target.port ? `:${target.port}` : ''}`
    : null;

  return {
    label: label || hostnameLabel || `Ringserver ${index + 1}`,
    source: {
      url,
      institutionName: label || null,
    },
    target,
  };
}

async function readRingserverEntries() {
  const filePath = serversListPath();
  try {
    const raw = await fsp.readFile(filePath, 'utf-8');
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if (error.code !== 'ENOENT') {
      console.log(`Unable to read ringserver list: ${error.message}`);
    }
    return [];
  }
}

async function buildRingserverTargets() {
  const entries = await readRingserverEntries();
  return entries
    .map((entry, index) => normalizeRingserverEntry(entry, index))
    .filter(Boolean);
}

async function probeRingserverTarget(entry) {
  const result = {
    label: entry.label,
    source: entry.source,
    target: entry.target,
    dns: { ok: false },
    tcp: { ok: false },
  };

  if (!entry?.target?.hostname) {
    result.error = 'Ringserver target missing';
    return result;
  }

  try {
    const lookup = await dns.lookup(entry.target.hostname);
    result.dns = { ok: true, address: lookup.address };
  } catch (error) {
    result.dns = { ok: false, error: error.message };
    return result;
  }

  await new Promise((resolve) => {
    const socket = net.createConnection(entry.target.port, entry.target.hostname, () => {
      result.tcp = { ok: true };
      socket.destroy();
      resolve();
    });

    socket.setTimeout(ringserverTcpTimeoutMs);
    socket.on('error', (error) => {
      result.tcp = { ok: false, error: error.message };
      resolve();
    });
    socket.on('timeout', () => {
      result.tcp = { ok: false, error: 'Connection timed out' };
      socket.destroy();
      resolve();
    });
  });

  return result;
}

function parseHostEntries(rawHosts) {
  if (!rawHosts || typeof rawHosts !== 'string') {
    return [];
  }
  return rawHosts
    .split(/[\s,]+/)
    .map((host) => host.trim())
    .filter((host) => host.length > 0);
}

function buildNtpTargets() {
  const hostStrings = [];
  const addHost = (value) => {
    if (!value) return;
    const trimmed = value.trim();
    if (!trimmed) return;
    if (hostStrings.includes(trimmed)) return;
    hostStrings.push(trimmed);
  };

  addHost(primaryNtpHost);
  addHost(process.env.NTP_SERVER); // legacy override
  parseHostEntries(ntpHostListRaw).forEach(addHost);

  if (hostStrings.length === 0) {
    hostStrings.push(defaultNtpHost);
  }

  return hostStrings
    .map((entry) => {
      const normalized = entry.replace(/^(ntp|udp):\/\//i, '');
      const parts = normalized.split(':');
      const hostname = parts[0]?.trim();
      if (!hostname) {
        return null;
      }
      const specifiedPort = parts.length > 1 ? Number(parts[parts.length - 1]) : null;
      return {
        hostname,
        port: Number.isFinite(specifiedPort) && specifiedPort > 0 ? specifiedPort : ntpPort,
        protocol: 'ntp',
        timeoutMs: ntpTimeoutMs,
      };
    })
    .filter(Boolean);
}

async function networkHealth(req, res) {
  const target = buildTarget();
  const responsePayload = {
    target,
    dns: { ok: false },
    tcp: { ok: false },
    https: { ok: false },
    ringservers: [],
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

  const ringserverTargets = await buildRingserverTargets();
  if (ringserverTargets.length > 0) {
    responsePayload.ringservers = await Promise.all(
      ringserverTargets.map((entry) => probeRingserverTarget(entry)),
    );
  }

  res.status(200).json({
    status: responseCodes.HEALTH_NETWORK_SUCCESS,
    message: 'Network health check complete',
    payload: responsePayload,
  });
}

async function timeHealth(req, res) {
  const targets = buildNtpTargets();
  const attempts = [];

  for (const target of targets) {
    try {
      const ntpResponse = await Sntp.time({
        host: target.hostname,
        port: target.port,
        timeout: target.timeoutMs > 0 ? target.timeoutMs : undefined,
      });
      const offsetMs = Number.isFinite(ntpResponse?.t) ? Math.round(ntpResponse.t) : null;
      const roundTripMs = Number.isFinite(ntpResponse?.d) ? Math.round(ntpResponse.d) : null;
      const serverDate = Number.isFinite(ntpResponse?.transmitTimestamp)
        ? ntpResponse.transmitTimestamp
        : null;

      attempts.push({
        hostname: target.hostname,
        port: target.port,
        ok: true,
      });

      res.status(200).json({
        status: responseCodes.HEALTH_TIME_SUCCESS,
        message: 'Time synchronization check complete',
        payload: {
          target,
          serverDate,
          offsetMs,
          roundTripMs,
          leapIndicator: ntpResponse?.leapIndicator,
          stratum: ntpResponse?.stratum,
          referenceId: ntpResponse?.referenceId,
          attempts,
        }
      });
      return;
    } catch (error) {
      attempts.push({
        hostname: target.hostname,
        port: target.port,
        ok: false,
        error: error.message,
      });
    }
  }

  res.status(500).json({
    status: responseCodes.HEALTH_TIME_ERROR,
    message: 'Time synchronization check failed',
    error: 'Unable to reach any configured NTP hosts',
    payload: { attempts },
  });
}

async function resourcesHealth(req, res) {
  try {
    const [disk, cpu] = await Promise.all([
      readDiskUsage(defaultDiskPath),
      getCpuUsageSnapshot(),
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
