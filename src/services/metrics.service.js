const fs = require('fs');
const path = require('path');

const DEFAULT_HEALTH_HISTORY_LIMIT = 120;
const DEFAULT_HISTORY_PERSIST_ENABLED = 'true';
const DEFAULT_HISTORY_FLUSH_MS = 250;

const localDbDir = () => process.env.LOCALDBS_DIRECTORY || './localDBs';
const historyFilePath = () => (
  process.env.METRICS_HEALTH_HISTORY_FILE
  || path.join(localDbDir(), 'health-history.json')
);

const healthTypes = ['network', 'time', 'resources', 'senderState'];

const state = {
  startedAt: new Date().toISOString(),
  http: {
    requestsTotal: 0,
    byMethod: {},
    byStatusClass: {},
    byPath: {},
  },
  alerts: {
    total: 0,
    byResult: {},
  },
  health: {
    checks: {},
    history: {},
  },
};

healthTypes.forEach((type) => {
  state.health.checks[type] = {
    total: 0,
    success: 0,
    error: 0,
    lastDurationMs: null,
    lastStatus: 'unknown',
    lastCheckedAt: null,
  };
  state.health.history[type] = [];
});

const parseInteger = (value, fallback, min = 0) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return fallback;
  const rounded = Math.floor(numeric);
  if (rounded < min) return fallback;
  return rounded;
};

const parseBoolean = (value, fallback = true) => {
  if (value === undefined || value === null || value === '') return fallback;
  if (typeof value === 'boolean') return value;
  const normalized = String(value).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'off'].includes(normalized)) return false;
  return fallback;
};

let historyLoaded = false;
let flushTimer = null;

function ensureMapCounter(mapRef, key) {
  if (!Object.prototype.hasOwnProperty.call(mapRef, key)) {
    mapRef[key] = 0;
  }
}

function trimHistory(type) {
  const maxEntries = parseInteger(process.env.METRICS_HEALTH_HISTORY_LIMIT, DEFAULT_HEALTH_HISTORY_LIMIT, 1);
  const bucket = state.health.history[type] || [];
  if (bucket.length > maxEntries) {
    state.health.history[type] = bucket.slice(bucket.length - maxEntries);
  }
}

async function writeJsonAtomic(filePath, payload) {
  const dir = path.dirname(filePath);
  const base = path.basename(filePath);
  const tmp = path.join(dir, `.${base}.${process.pid}.${Date.now()}.tmp`);
  await fs.promises.mkdir(dir, { recursive: true });
  await fs.promises.writeFile(tmp, JSON.stringify(payload));
  await fs.promises.rename(tmp, filePath);
}

function scheduleHistoryFlush() {
  const enabled = parseBoolean(process.env.METRICS_PERSIST_HEALTH_HISTORY, DEFAULT_HISTORY_PERSIST_ENABLED === 'true');
  if (!enabled) return;
  if (flushTimer) return;

  const delayMs = parseInteger(process.env.METRICS_HEALTH_HISTORY_FLUSH_MS, DEFAULT_HISTORY_FLUSH_MS, 50);
  flushTimer = setTimeout(async () => {
    flushTimer = null;
    try {
      await writeJsonAtomic(historyFilePath(), {
        updatedAt: new Date().toISOString(),
        history: state.health.history,
      });
    } catch (error) {
      if (process.env.NODE_ENV !== 'test') {
        console.log(`Failed to persist health history: ${error.message || error}`);
      }
    }
  }, delayMs);

  if (typeof flushTimer.unref === 'function') {
    flushTimer.unref();
  }
}

function loadPersistedHistory() {
  if (historyLoaded) return;
  historyLoaded = true;

  try {
    const raw = fs.readFileSync(historyFilePath(), 'utf-8');
    const parsed = JSON.parse(raw);
    const persisted = parsed?.history || {};
    healthTypes.forEach((type) => {
      if (Array.isArray(persisted[type])) {
        state.health.history[type] = persisted[type];
        trimHistory(type);
      }
    });
  } catch (_error) {
    // No persisted history yet; start fresh.
  }
}

function normalizePath(value = '') {
  const source = String(value || '').trim();
  if (!source) return '/';
  const stripped = source.split('?')[0];
  return stripped || '/';
}

function getStatusClass(statusCode) {
  const numeric = Number(statusCode);
  if (!Number.isFinite(numeric) || numeric <= 0) return 'unknown';
  return `${Math.floor(numeric / 100)}xx`;
}

function sanitizeMeta(meta = {}) {
  if (!meta || typeof meta !== 'object') return {};
  const safe = {};
  Object.keys(meta).forEach((key) => {
    const value = meta[key];
    if (value === null || value === undefined) return;
    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
      safe[key] = value;
      return;
    }
    if (Array.isArray(value)) {
      safe[key] = value.slice(0, 10);
      return;
    }
    if (typeof value === 'object') {
      safe[key] = '[object]';
    }
  });
  return safe;
}

function recordHttpRequest({
  method,
  path: requestPath,
  statusCode,
  durationMs,
} = {}) {
  const http = state.http;
  const normalizedMethod = String(method || 'UNKNOWN').toUpperCase();
  const normalizedPath = normalizePath(requestPath);
  const statusClass = getStatusClass(statusCode);

  http.requestsTotal += 1;
  ensureMapCounter(http.byMethod, normalizedMethod);
  http.byMethod[normalizedMethod] += 1;

  ensureMapCounter(http.byStatusClass, statusClass);
  http.byStatusClass[statusClass] += 1;

  if (!http.byPath[normalizedPath]) {
    http.byPath[normalizedPath] = {
      count: 0,
      lastStatusCode: null,
      lastDurationMs: null,
      avgDurationMs: null,
    };
  }

  const bucket = http.byPath[normalizedPath];
  const previousCount = bucket.count;
  bucket.count += 1;
  bucket.lastStatusCode = statusCode || null;
  bucket.lastDurationMs = Number.isFinite(durationMs) ? Number(durationMs.toFixed(1)) : null;
  if (Number.isFinite(durationMs)) {
    const priorAvg = Number.isFinite(bucket.avgDurationMs) ? bucket.avgDurationMs : durationMs;
    const updatedAvg = ((priorAvg * previousCount) + durationMs) / bucket.count;
    bucket.avgDurationMs = Number(updatedAvg.toFixed(1));
  }
}

function recordAlertPost(result, meta = {}) {
  const normalized = String(result || 'unknown');
  state.alerts.total += 1;
  ensureMapCounter(state.alerts.byResult, normalized);
  state.alerts.byResult[normalized] += 1;
  const _meta = sanitizeMeta(meta);
  void _meta;
}

function recordHealthCheck(type, {
  ok = false,
  durationMs = null,
  meta = {},
} = {}) {
  loadPersistedHistory();
  const normalizedType = healthTypes.includes(type) ? type : 'resources';
  const checks = state.health.checks[normalizedType];

  checks.total += 1;
  checks.lastStatus = ok ? 'success' : 'error';
  checks.lastCheckedAt = new Date().toISOString();
  checks.lastDurationMs = Number.isFinite(durationMs) ? Number(durationMs.toFixed(1)) : null;
  if (ok) checks.success += 1;
  else checks.error += 1;

  state.health.history[normalizedType].push({
    at: checks.lastCheckedAt,
    ok: Boolean(ok),
    durationMs: checks.lastDurationMs,
    ...sanitizeMeta(meta),
  });
  trimHistory(normalizedType);
  scheduleHistoryFlush();
}

function getMetricsSnapshot() {
  loadPersistedHistory();
  return {
    generatedAt: new Date().toISOString(),
    startedAt: state.startedAt,
    uptimeSec: Math.floor(process.uptime()),
    http: state.http,
    alerts: state.alerts,
    health: state.health,
  };
}

module.exports = {
  recordHttpRequest,
  recordAlertPost,
  recordHealthCheck,
  getMetricsSnapshot,
};
