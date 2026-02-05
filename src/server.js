// import app from './app'
const app = require('./app')
const { createLocalFileStoreDir } = require('./services/utils')
const { initializeStreamsObject, spawnSlink2dali } = require('./controllers/stream.utils')
let { streamsObject } = require('./controllers/stream.utils')
const { refreshIfExpiringSoon } = require('./services/device.service')

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
  } catch (error) {
    console.error('Error occurred:', error);
  }
}

// Call the main function
init();

const isTestRuntime = process.env.NODE_ENV === 'test' || process.env.JEST_WORKER_ID !== undefined;

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
    await refreshIfExpiringSoon();
  } catch (error) {
    console.log(`Proactive token refresh failed: ${error.message || error}`);
  } finally {
    const interval = Number(process.env.REFRESH_CHECK_INTERVAL_MS || 15 * 60 * 1000);
    refreshTimer = setTimeout(scheduleRefresh, interval);
    if (typeof refreshTimer.unref === 'function') {
      refreshTimer.unref();
    }
  }
};

if (!isTestRuntime) {
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
