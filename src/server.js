const fs = require('fs');
const path = require('path');
// import app from './app'
const app = require('./app')
const { createLocalFileStoreDir } = require('./services/utils')
const { initializeStreamsObject, spawnSlink2dali } = require('./controllers/stream.utils')
let { streamsObject } = require('./controllers/stream.utils')
const { refreshIfExpiringSoonWithStatus, syncRshakeAlertCredential } = require('./services/device.service')
const rshakeAlertsService = require('./services/rshakeAlerts.service')
const serversController = require('./controllers/servers.controller')

// Asynchronous function for:
// 1. creating local file store,
// 2. initializing streamsObject dictionary, 
// 3. then start streaming on each supplied url.
async function init() {
  try {
    await createLocalFileStoreDir();
    streamsObject = await initializeStreamsObject();
    console.log(streamsObject)

    for (const url in streamsObject) {
      if (streamsObject.hasOwnProperty(url)) {
        try {
          await spawnSlink2dali(url);
        } catch (error) {
          console.error(`Error starting stream for ${url}: ${error?.message || error}`);
        }
      }
    }

    if (process.env.NODE_ENV !== 'test') {
      const defaultRingserverResult = await serversController.ensureDefaultRingserverOnStartup();
      if (defaultRingserverResult?.added) {
        console.log(`Default ringserver added on startup: ${defaultRingserverResult.server?.url}`);
      } else if (defaultRingserverResult?.attempted) {
        console.log(`Default ringserver startup check: ${defaultRingserverResult.reason}`);
      } else {
        console.log(`Default ringserver startup skipped: ${defaultRingserverResult?.reason}`);
      }
    }
  } catch (error) {
    console.error('Error occurred:', error);
  }
}

// Call the main function
init();

const isTestRuntime = process.env.NODE_ENV === 'test' || process.env.JEST_WORKER_ID !== undefined;
const localDbsRoot = process.env.LOCALDBS_DIRECTORY || './localDBs';
const tokenRefreshFailureThreshold = Number(process.env.TOKEN_REFRESH_FAILED_CONSECUTIVE_THRESHOLD || 2);
const tokenRefreshSuccessCooldownSec = Number(process.env.TOKEN_REFRESH_SUCCESS_COOLDOWN_SEC || 86400);
const tokenRefreshAlertsEnabled = String(process.env.TOKEN_REFRESH_ALERTS_ENABLED || 'true').toLowerCase() !== 'false';
const tokenRefreshAlertStatePath = process.env.TOKEN_REFRESH_ALERT_STATE_FILE
  || path.join(localDbsRoot, 'token-refresh-alert-state.json');

let tokenAlertState = {
  failureCount: 0,
  failureActive: false,
  lastSuccessAlertAt: 0,
};
let tokenAlertStateLoaded = false;

function safeInteger(value, fallback, min = 0) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return fallback;
  const rounded = Math.floor(numeric);
  if (rounded < min) return fallback;
  return rounded;
}

function normalizeTokenAlertState(raw = {}) {
  return {
    failureCount: safeInteger(raw.failureCount, 0, 0),
    failureActive: raw.failureActive === true,
    lastSuccessAlertAt: safeInteger(raw.lastSuccessAlertAt, 0, 0),
  };
}

async function loadTokenAlertState() {
  if (tokenAlertStateLoaded) return;
  tokenAlertStateLoaded = true;
  try {
    const raw = await fs.promises.readFile(tokenRefreshAlertStatePath, 'utf-8');
    tokenAlertState = normalizeTokenAlertState(JSON.parse(raw));
  } catch (_error) {
    tokenAlertState = normalizeTokenAlertState();
  }
}

async function saveTokenAlertState() {
  try {
    const dir = path.dirname(tokenRefreshAlertStatePath);
    const baseName = path.basename(tokenRefreshAlertStatePath);
    const tmpPath = path.join(dir, `.${baseName}.${process.pid}.${Date.now()}.tmp`);
    await fs.promises.mkdir(dir, { recursive: true });
    await fs.promises.writeFile(
      tmpPath,
      JSON.stringify(tokenAlertState),
    );
    await fs.promises.rename(tmpPath, tokenRefreshAlertStatePath);
  } catch (error) {
    console.log(`Failed to persist token refresh alert state: ${error.message || error}`);
  }
}

async function postTokenRefreshAlert({
  type = 'device.alert',
  alertCode,
  severity,
  status,
  summary,
  details = {},
}) {
  if (!tokenRefreshAlertsEnabled) {
    return { str: 'disabled' };
  }

  return rshakeAlertsService.postRshakeAlert({
    type,
    alertCode,
    severity,
    status,
    summary,
    details: {
      source: 'sender-token-auto-refresh',
      notificationScope: 'admin-only',
      ...details,
    },
    dedupeKey: `token-refresh.${String(alertCode || 'alert').toLowerCase()}`,
  });
}

async function handleTokenRefreshAlerts(refreshResult) {
  if (!refreshResult || !refreshResult.attempted) {
    return;
  }

  await loadTokenAlertState();

  const nowSeconds = Math.floor(Date.now() / 1000);
  const threshold = safeInteger(tokenRefreshFailureThreshold, 2, 1);
  const successCooldownSec = safeInteger(tokenRefreshSuccessCooldownSec, 86400, 0);
  const tokenStatusBefore = refreshResult.tokenStatusBefore || {};
  const tokenStatusAfter = refreshResult.tokenStatusAfter || {};

  if (!refreshResult.success) {
    tokenAlertState.failureCount += 1;
    if (!tokenAlertState.failureActive && tokenAlertState.failureCount >= threshold) {
      await postTokenRefreshAlert({
        type: 'device.alert',
        alertCode: 'TOKEN_REFRESH_FAILED',
        severity: 'warning',
        status: 'Error',
        summary: 'Sender auto-refresh token attempts are failing.',
        details: {
          attemptCount: tokenAlertState.failureCount,
          failureThreshold: threshold,
          reason: refreshResult.errorMessage || 'Unknown token refresh error',
          errorCode: refreshResult.errorCode || null,
          errorStatus: refreshResult.errorStatus || null,
          expiresAtBefore: tokenStatusBefore.expiresAt || null,
          secondsToExpiryBefore: tokenStatusBefore.secondsToExpiry ?? null,
        },
      });
      tokenAlertState.failureActive = true;
    }

    await saveTokenAlertState();
    return;
  }

  const shouldPostRecovery = tokenAlertState.failureActive;
  tokenAlertState.failureCount = 0;
  tokenAlertState.failureActive = false;

  if (shouldPostRecovery) {
    await postTokenRefreshAlert({
      type: 'device.recovery',
      alertCode: 'TOKEN_REFRESH_RECOVERY',
      severity: 'info',
      status: 'Recovered',
      summary: 'Sender auto-refresh token attempts recovered.',
      details: {
        expiresAtBefore: tokenStatusBefore.expiresAt || null,
        expiresAtAfter: tokenStatusAfter.expiresAt || null,
        secondsToExpiryAfter: tokenStatusAfter.secondsToExpiry ?? null,
      },
    });
  }

  const elapsedSinceSuccessAlert = nowSeconds - tokenAlertState.lastSuccessAlertAt;
  const shouldPostSuccess = !shouldPostRecovery
    && (tokenAlertState.lastSuccessAlertAt === 0 || elapsedSinceSuccessAlert >= successCooldownSec);

  if (shouldPostSuccess) {
    await postTokenRefreshAlert({
      type: 'device.alert',
      alertCode: 'TOKEN_REFRESH_SUCCESS',
      severity: 'info',
      status: 'AutoRefresh',
      summary: 'Sender access token auto-refresh succeeded.',
      details: {
        expiresAtBefore: tokenStatusBefore.expiresAt || null,
        expiresAtAfter: tokenStatusAfter.expiresAt || null,
        secondsToExpiryAfter: tokenStatusAfter.secondsToExpiry ?? null,
      },
    });
    tokenAlertState.lastSuccessAlertAt = nowSeconds;
  }

  await saveTokenAlertState();
}

// Proactive token refresh scheduler (runs with the server process)
let refreshTimer = null;
const clearRefreshTimer = () => {
  if (refreshTimer) {
    clearTimeout(refreshTimer);
    refreshTimer = null;
  }
};

const scheduleRefresh = async () => {
  try {
    const refreshResult = await refreshIfExpiringSoonWithStatus();
    await handleTokenRefreshAlerts(refreshResult);
    if (refreshResult?.attempted && !refreshResult.success) {
      console.log(`Proactive token refresh failed: ${refreshResult.errorMessage || 'Unknown refresh error'}`);
    }
  } catch (error) {
    console.log(`Proactive token refresh scheduler error: ${error.message || error}`);
  } finally {
    const interval = Number(process.env.REFRESH_CHECK_INTERVAL_MS || 15 * 60 * 1000);
    refreshTimer = setTimeout(scheduleRefresh, interval);
    if (typeof refreshTimer.unref === 'function') {
      refreshTimer.unref();
    }
  }
};

const syncAlertCredentialOnStartup = async () => {
  try {
    const result = await syncRshakeAlertCredential({ allowTokenRefresh: true });
    if (result?.str === 'success') {
      console.log('RShake alert credential synced from Earthquake Hub.');
    }
  } catch (error) {
    console.log(`Startup alert credential sync skipped: ${error?.message || error}`);
  }
};

if (!isTestRuntime) {
  syncAlertCredentialOnStartup();
  scheduleRefresh();

  const handleShutdownSignal = (signal) => {
    console.log(`Received ${signal}, clearing proactive token refresh timer.`);
    clearRefreshTimer();
    // Re-emit so default shutdown behaviour still happens.
    process.kill(process.pid, signal);
  };

  process.once('SIGINT', () => handleShutdownSignal('SIGINT'));
  process.once('SIGTERM', () => handleShutdownSignal('SIGTERM'));
  process.once('exit', clearRefreshTimer);
}

const port = process.env.NODE_ENV === 'production'
  ? process.env.BACKEND_PROD_PORT
  : process.env.BACKEND_DEV_PORT;

const ip = process.env.NODE_ENV === 'production'
  ? process.env.BACKEND_PROD_IP
  : process.env.BACKEND_DEV_IP;

app.listen(port, ip, () => {
  console.log(`App listening on: ${ip}:${port}`);
  process.env.NODE_ENV === 'production'
   ? console.log(`Production client expected (by CORS) at: http://${process.env.CLIENT_PROD_IP}:${process.env.CLIENT_PROD_PORT}`)
   : console.log(`Development client expected (by CORS) at: http://${process.env.CLIENT_DEV_IP}:${process.env.CLIENT_DEV_PORT}`)
})
