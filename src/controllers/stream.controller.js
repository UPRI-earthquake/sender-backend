const fs = require('fs')
const path = require('path')
const { spawn } = require('child_process');
const { read_network, read_station } = require('../routes/utils');

let streamsObject = {};

// Function for initializing streamsObject dictionary
async function initializeStreamsObject() {
  try {
    const localFileStoreDir = process.env.LOCALDBS_DIRECTORY
    const jsonString = await fs.promises.readFile(`${localFileStoreDir}/servers.json`, 'utf-8');
    const serversList = JSON.parse(jsonString);

    // Iterate over the serversList and update the StreamsObject
    serversList.forEach((server) => {
      const { url, hostName } = server;
      if (!streamsObject[url]) {
        // Add the server to StreamsObject if it's a unique URL
        streamsObject[url] = {
          hostName: hostName,
          childProcess: null,
          status: 'Not Streaming',
        };
      }
    });

    return streamsObject;
  } catch (error) {
    console.log(`Error reading file: ${error}`);
    return {};
  }
}

// Function that checks whether the streamsObject dictionary is initialized or not; returns streamsObject.
async function getStreamsObject() {
  if (!streamsObject) {
    streamsObject = await initializeStreamsObject();
    return streamsObject;
  } else {
    return streamsObject;
  }
}

// Function for updating the status of the specified url in streamsObject dictionary
async function updateStreamStatus(url, childProcess, status) {
  if (streamsObject.hasOwnProperty(url)) {
    streamsObject[url].status = status;
    streamsObject[url].childProcess = childProcess;
  }

  return streamsObject;
}


async function addNewStream(url, hostName) {
  streamsObject[url] = {
    hostName: hostName,
    childProcess: null,
    status: 'Not Streaming'
  };
  console.log(`New object added to streamsObject dictionary: ${streamsObject}`)
}

// Function for spawning slink2dali child process
async function spawnSlink2dali(receiver_ringserver) {
  let childProcess = null;

  try {
    const localFileStoreDir = process.env.LOCALDBS_DIRECTORY
    const jsonString = await fs.promises.readFile(`${localFileStoreDir}/token.json`, 'utf-8');
    const token = JSON.parse(jsonString);

    const command = `${process.env.SLINK2DALIPATH}`;
    const network = read_network()
    const station = read_station()
    const net_sta = `${network}_${station}`;
    const sender_slink2dali = 'docker-host:18000';
    const options = ['-vvv', '-a', token.accessToken, '-S', net_sta, sender_slink2dali, receiver_ringserver];

    childProcess = spawn(command, options); // Execute the command using spawn

    let hasError = false; // Flag to track if an error occurred

    // Listen for 'error' event from the child process
    childProcess.on('error', (error) => {
      console.error(`Error executing command: ${error}`);
      hasError = true;
    });

    // Listen for 'close' event from the child process
    childProcess.on('close', (code, signal) => {
      console.log(`Child process closed with code ${code} and signal ${signal}`);
    });

    // Listen for 'exit' event from the child process
    childProcess.on('exit', async (code, signal) => {
      console.log(`Child process exited with code ${code} and signal ${signal}`);

      if (hasError) {
        // Cleanup functions: 
        childProcess.kill(); // Terminate the child process
        await updateStreamStatus(receiver_ringserver, null, 'Not Streaming'); // Update the status to 'Not Streaming'
      }
    });

    // Listen for 'stdout' event from the child process
    childProcess.stdout.on('data', (data) => {
      console.log(`Command output: ${data}`); // Log output from slink2dali  

      // Listen for 'error' in slink2dali logs
      if (data.includes('error')) {
        console.error('Error encountered in slink2dali logs');
        // Set the error flag to true
        hasError = true;
      }
    });

    // Listen for 'stderr' event from the child process
    childProcess.stderr.on('data', (data) => {
      console.error(`Command error: ${data}`);
    });

    await updateStreamStatus(receiver_ringserver, childProcess, 'Streaming'); // Update the status to 'streaming'
    console.log('Child process spawned successfully');
  } catch (error) {
    console.error(`Error spawning slink2dali: ${error}`);
    if (childProcess) {
      childProcess.kill();
    }
    // Handle the error and throw an exception
    throw new Error('Error spawning child process');
  }
}


module.exports = {
  initializeStreamsObject,
  getStreamsObject,
  updateStreamStatus,
  addNewStream,
  spawnSlink2dali
};
