const fs = require('fs')
const { spawn } = require('child_process');
const { read_network, read_station } = require('../services/utils');
const deviceService = require('../services/device.service');

const MAX_LOG_ENTRIES = 20;
const localStoreDir = () => process.env.LOCALDBS_DIRECTORY || './localDBs';

let streamsObject = {};
const verboseSlinkLogs = process.env.SLINK2DALI_VERBOSE_LOGS === 'true';
const slinkVerbosityFlag = process.env.SLINK2DALI_VERBOSITY || '-v';

function createStreamEntry(institutionName, status = 'Not Streaming') {
  return {
    institutionName: institutionName || null,
    childProcess: null,
    status,
    retryCount: 0,
    logs: [],
    attemptLogs: {},
    attemptId: 0,
    activeAttemptId: null,
    lastSuccessTs: null,
  };
}

async function readServersFile() {
  try {
    const jsonString = await fs.promises.readFile(`${localStoreDir()}/servers.json`, 'utf-8');
    return JSON.parse(jsonString);
  } catch (error) {
    console.log(`Error reading servers.json: ${error}`);
    return [];
  }
}

function appendStreamLog(url, message) {
  if (!message || !url) {
    return;
  }
  const entry = streamsObject[url];
  if (!entry) {
    return;
  }
  const trimmed = message.toString().trim();
  if (!trimmed) {
    return;
  }
  const logLine = `[${new Date().toISOString()}] ${trimmed}`;
  const activeAttemptId = entry.activeAttemptId ?? 'latest';
  if (!entry.attemptLogs) {
    entry.attemptLogs = {};
  }
  if (!entry.attemptLogs[activeAttemptId]) {
    entry.attemptLogs[activeAttemptId] = [];
  }
  const targetLogs = entry.attemptLogs[activeAttemptId];
  entry.logs = targetLogs;
  targetLogs.push(logLine);
  if (targetLogs.length > MAX_LOG_ENTRIES) {
    entry.attemptLogs[activeAttemptId] = targetLogs.slice(-MAX_LOG_ENTRIES);
    entry.logs = entry.attemptLogs[activeAttemptId];
  }
}

// Function for initializing streamsObject dictionary
async function initializeStreamsObject() {
  try {
    const serversList = await readServersFile();

    // Iterate over the serversList and update the StreamsObject
    serversList.forEach((server) => {
      const { url, institutionName } = server;
      if (!streamsObject[url]) {
        // Add the server to StreamsObject if it's a unique URL
        streamsObject[url] = createStreamEntry(institutionName, 'Not Streaming');
      }
    });

    return streamsObject;
  } catch (error) {
    console.log(`Error initializing streams object: ${error}`);
    return {};
  }
}

// Function that checks whether the streamsObject dictionary is initialized or not; returns streamsObject.
async function getStreamsObject() {
  if (!streamsObject || Object.keys(streamsObject).length === 0) {
    streamsObject = await initializeStreamsObject();
  }
  return streamsObject;
}

async function reconcileStreamsWithFile() {
  const serversList = await readServersFile();
  await getStreamsObject();

  const urlsInFile = new Set(serversList.map((server) => server.url));
  const removedUrls = [];

  // Remove any streams that no longer exist in servers.json
  Object.keys(streamsObject).forEach((url) => {
    if (!urlsInFile.has(url)) {
      const entry = streamsObject[url];
      if (entry?.childProcess && !entry.childProcess.killed) {
        try {
          entry.childProcess.kill('SIGTERM');
        } catch (error) {
          console.log(`Error killing child process during reconciliation for ${url}: ${error}`);
        }
      }
      delete streamsObject[url];
      removedUrls.push(url);
    }
  });

  // Ensure each entry from servers.json exists in the cache
  serversList.forEach(({ url, institutionName }) => {
    if (!streamsObject[url]) {
      streamsObject[url] = createStreamEntry(institutionName, 'Not Streaming');
    } else if (institutionName && !streamsObject[url].institutionName) {
      streamsObject[url].institutionName = institutionName;
    }
    if (!Object.prototype.hasOwnProperty.call(streamsObject[url], 'lastSuccessTs')) {
      streamsObject[url].lastSuccessTs = null;
    }
  });

  return { streamsObject, removedUrls };
}

/* 
Function for updating the status of the specified url in streamsObject dictionary
  url: ringserver url
  childProcess: child process object
  retryFlag: increment retry count by 1, if true
  resetFlag: reset retryCount to 0,if true
*/
async function updateStreamStatus(url, childProcess, retryFlag, resetFlag) {
  await getStreamsObject();
  const streamEntry = streamsObject[url];

  if (!streamEntry) {
    return;
  }

  streamEntry.childProcess = childProcess;

  if (retryFlag) {
    streamEntry.retryCount += 1;
  }

  if (resetFlag) {
    streamEntry.retryCount = 0;
    streamEntry.logs = [];
    streamEntry.attemptLogs = {};
    streamEntry.activeAttemptId = null;
    streamEntry.lastSuccessTs = Date.now();
  }
  
  // Set status based on number of spawn retries
  if (streamEntry.retryCount === 0) {
    streamEntry.status = 'Streaming';
    if (!resetFlag && !streamEntry.lastSuccessTs) {
      streamEntry.lastSuccessTs = Date.now();
    }
  } else if (streamEntry.retryCount <= 3) {
    streamEntry.status = 'Connecting';
  } else {
    streamEntry.status = 'Error';
  }

  return streamEntry;
}

async function markStreamHealthy(url, childProcess) {
  await getStreamsObject();
  const streamEntry = streamsObject[url];
  if (!streamEntry) {
    return null;
  }

  const alreadyStreaming = streamEntry.status === 'Streaming' && streamEntry.retryCount === 0;
  if (alreadyStreaming) {
    streamEntry.lastSuccessTs = streamEntry.lastSuccessTs || Date.now();
    return streamEntry;
  }

  const updated = await updateStreamStatus(url, childProcess, false, true);
  if (updated && !updated.lastSuccessTs) {
    updated.lastSuccessTs = Date.now();
  }
  return updated;
}

// Function for adding new stream to streamsObject dictionary
async function addNewStream(url, institutionName) {
  if (!streamsObject || Object.keys(streamsObject).length === 0) {
    streamsObject = await initializeStreamsObject();
    console.log(`streamsObject reinitialized`)
  }

  streamsObject[url] = createStreamEntry(institutionName || url, 'Connecting');
  console.log(`New object added to streamsObject dictionary: ${streamsObject}`)
}

// Function for removing a stream to streamsObject dictionary
async function clearStreamsObject() {
  console.log(`streamsObject: ${streamsObject}`)
  const urls = Object.keys(streamsObject);
  for (const url of urls) {
    const childProcess = streamsObject[url]?.childProcess;
    if (childProcess && !childProcess.killed) {
      try {
        childProcess.kill('SIGTERM');
      } catch (error) {
        console.log(`Error killing child process for ${url}: ${error}`);
      }
    }
    delete streamsObject[url];
  }
  console.log(`streamsObject dictionary cleared`)

  return 'success';
}

async function removeStream(url) {
  await getStreamsObject();
  const entry = streamsObject[url];
  if (!entry) {
    return false;
  }

  if (entry.childProcess && !entry.childProcess.killed) {
    try {
      entry.childProcess.kill('SIGTERM');
    } catch (error) {
      console.log(`Error killing child process for ${url}: ${error}`);
    }
  }

  delete streamsObject[url];
  return true;
}

// Function for spawning slink2dali child process
async function spawnSlink2dali(receiver_ringserver) {
  let childProcess = null;

  try {
    await getStreamsObject();
    if (!streamsObject[receiver_ringserver]) {
      streamsObject[receiver_ringserver] = createStreamEntry(receiver_ringserver, 'Connecting');
    }

    const streamEntry = streamsObject[receiver_ringserver];
    streamEntry.attemptId = (streamEntry.attemptId || 0) + 1;
    streamEntry.activeAttemptId = streamEntry.attemptId;
    streamEntry.attemptLogs = {};
    streamEntry.attemptLogs[streamEntry.activeAttemptId] = [];
    streamEntry.logs = streamEntry.attemptLogs[streamEntry.activeAttemptId];

    const token = await deviceService.ensureValidAccessToken();

    const command = `${process.env.SLINK2DALIPATH}`;
    const network = read_network()
    const station = read_station()
    const net_sta = `${network}_${station}`;
    const sender_slink2dali = 'docker-host:18000'; // TODO: On development environment, this should be changed
    const options = [];
    if (slinkVerbosityFlag) {
      options.push(slinkVerbosityFlag);
    }
    options.push('-a', token, '-S', net_sta, sender_slink2dali, receiver_ringserver);

    childProcess = spawn(command, options); // Execute the command using spawn

    let hasError = false; // Flag to track if an error occurred

    // Listen for 'error' event from the child process
    childProcess.on('error', (error) => {
      console.error(`Error executing command: ${error}`);
      appendStreamLog(receiver_ringserver, `Process error: ${error.message || error}`);
      hasError = true;
    });

    // Listen for 'close' event from the child process
    childProcess.on('close', (code, signal) => {
      console.log(`Child process closed with code ${code} and signal ${signal}`);
    });

    // Listen for 'exit' event from the child process
    childProcess.on('exit', async (code, signal) => {
      console.log(`Child process exited with code ${code} and signal ${signal}`);

      const terminatedOnPurpose = signal === 'SIGTERM';
      const exitCode = typeof code === 'number' ? code : null;
      const failed = hasError || (!terminatedOnPurpose && exitCode !== 0);

      if (failed) {
        appendStreamLog(receiver_ringserver, `Process exited with code ${exitCode ?? 'null'} (signal ${signal ?? 'null'})`);
        // Cleanup functions: 
        const updatedStream = await updateStreamStatus(receiver_ringserver, null, true, false); // Increment the retryCount
        
        console.log(`updatedStream: ${updatedStream}`)

        if (updatedStream != undefined) {
          console.log(`pid: ${childProcess.pid}`)
          console.log(`retryCount: ${updatedStream.retryCount}`)
          
          // Respawn slink2dali with interval depending on the number of retries
          if (updatedStream.retryCount <= 3) {
            setTimeout(async () => {
              console.log('Respawning slink2dali...');
              await spawnSlink2dali(receiver_ringserver);
            }, 1000*30); // Set 30-second-timeout (time is in milliseconds) if retryCount is less than or equal to 3 
          } 
          else { // retryCount > 3
            setTimeout(async () => {
              console.log('Respawning slink2dali...');
              await spawnSlink2dali(receiver_ringserver);
            }, 1000*60*2); // Set 2-minute-timeout (time is in milliseconds) if retryCount is more than to 3
          }
        }
      }
    });

    // Listen for 'stdout' event from the child process
    childProcess.stdout.on('data', async (data) => {
      const message = data.toString();
      const normalizedMessage = message.toLowerCase();
      if (verboseSlinkLogs) {
        console.log(`Command output: ${message.trim()}`); // Log output from slink2dali  
      }

      const hasAuthErrorKeyword =
        normalizedMessage.includes('unauthorized') ||
        normalizedMessage.includes('unauthenticated') ||
        normalizedMessage.includes('unauth') ||
        normalizedMessage.includes('forbidden') ||
        normalizedMessage.includes('authentication') ||
        normalizedMessage.includes('authorization') ||
        normalizedMessage.includes('401') ||
        normalizedMessage.includes('403');
      const hasErrorKeyword = normalizedMessage.includes('error') || hasAuthErrorKeyword;
      const isRetryLog = normalizedMessage.includes('re-connecting') || normalizedMessage.includes('trying again') || normalizedMessage.includes('retry');
      const hasHealthySignal =
        normalizedMessage.includes('write_success') ||
        normalizedMessage.includes('successfully') ||
        normalizedMessage.includes(' version') ||
        normalizedMessage.includes('connected to datalink') ||
        normalizedMessage.includes('keep alive') ||
        normalizedMessage.includes('packet');

      if (hasErrorKeyword) {
        console.error('Error encountered in slink2dali logs');
        appendStreamLog(receiver_ringserver, message);
        // Set the error flag to true
        hasError = true;
      }
      else if (hasHealthySignal || (!isRetryLog && normalizedMessage.trim())) {
        try {
          await markStreamHealthy(receiver_ringserver, childProcess); // Reset the retryCount to 0 and mark streaming
        } catch (markError) {
          console.log(`Unable to mark ${receiver_ringserver} healthy: ${markError}`);
        }
      }
    });

    // Listen for 'stderr' event from the child process
    childProcess.stderr.on('data', (data) => {
      console.error(`Command error: ${data}`);
      appendStreamLog(receiver_ringserver, data);
      hasError = true;
    });

    console.log('Child process spawned successfully');
  } catch (error) {
    console.error(`Error spawning slink2dali: ${error}`);
    if (childProcess) {
      childProcess.kill();
    }
    if (streamsObject[receiver_ringserver]) {
      await updateStreamStatus(receiver_ringserver, null, true, false);
      streamsObject[receiver_ringserver].status = 'Error';
      appendStreamLog(receiver_ringserver, error.message || 'Unexpected spawning error');
    }
    // Prevent crashes; mark error and return so caller can continue running
    return null;
  }
}


module.exports = {
  initializeStreamsObject,
  getStreamsObject,
  updateStreamStatus,
  addNewStream,
  spawnSlink2dali,
  clearStreamsObject,
  removeStream,
  reconcileStreamsWithFile,
  streamsObject,
};
