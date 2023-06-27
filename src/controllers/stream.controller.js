const fs = require('fs')
const path = require('path')
const axios = require('axios')
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
          retryCount: 0
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

/* 
Function for updating the status of the specified url in streamsObject dictionary
  url: ringserver url
  childProcess: child process object
  retryFlag: increment retry count by 1, if true
  resetFlag: reset retryCount to 0,if true
*/
async function updateStreamStatus(url, childProcess, retryFlag, resetFlag) {
  if (streamsObject.hasOwnProperty(url)) {
    streamsObject[url].childProcess = childProcess;

    if (retryFlag) {
      streamsObject[url].retryCount += 1;
    }

    if (resetFlag) {
      streamsObject[url].retryCount = 0;
    }
    
    // Set status based on number of spawn retries
    if (streamsObject[url].retryCount === 0) {
      streamsObject[url].status = 'Streaming';
    } else if (streamsObject[url].retryCount <= 3) {
      streamsObject[url].status = 'Connecting';
    } else if (streamsObject[url].retryCount > 3) {
      streamsObject[url].status = 'Error';
    }
  }

  return streamsObject[url];
}


async function addNewStream(url, hostName) {
  streamsObject[url] = {
    hostName: hostName,
    childProcess: null,
    status: 'Not Streaming',
    retryFlag: 0
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
        const updatedStream = await updateStreamStatus(receiver_ringserver, null, true, false); // Increment the retryCount
        console.log(childProcess.pid)
        console.log(updatedStream.retryCount)
        
        // Respawn slink2dali with interval depending on the number of retries
        if (updatedStream.retryCount <= 3) {
          setTimeout(async () => {
            console.log('Respawning slink2dali...');
            await spawnSlink2dali(receiver_ringserver);
          }, 30000); // Set 30-second-timeout if retryCount is less than or equal to 3 
        } 
        else { // retryCount > 3
          setTimeout(async () => {
            console.log('Respawning slink2dali...');
            await spawnSlink2dali(receiver_ringserver);
          }, 300000); // Set 5-minute-timeout if retryCount is more than to 3
        }
      }
    });

    // Listen for 'stdout' event from the child process
    childProcess.stdout.on('data', async (data) => {
      console.log(`Command output: ${data}`); // Log output from slink2dali  

      // Listen for 'error' in slink2dali logs
      if (data.includes('error')) {
        console.error('Error encountered in slink2dali logs');
        // Set the error flag to true
        hasError = true;
      }
      
      // Listen for 'WRITE_OK' in slink2dali logs
      if (data.includes('WRITE_OK')) {
        await updateStreamStatus(receiver_ringserver, childProcess, false, true); // Reset the retryCount to 0
      }
    });

    // Listen for 'stderr' event from the child process
    childProcess.stderr.on('data', (data) => {
      console.error(`Command error: ${data}`);
    });

    await updateStreamStatus(receiver_ringserver, childProcess, false, false); // Do not increment the retryFlag count
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
