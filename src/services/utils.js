const fs = require('fs')

function read_network() {
  try {
    const network = fs.readFileSync('/opt/settings/sys/NET.txt', 'utf8');
    return network.trim();
  } catch (error) {
    // log and move on
    console.log(error)
  }
  return '';
}

function read_station() {
  try {
    const station = fs.readFileSync('/opt/settings/sys/STN.txt', 'utf8');
    return station.trim();
  } catch (error) {
    // log and move on
    console.log(error)
  }
  return '';
}
// A function for getting the device streamId from rshake
function generate_streamId() {
  let network = read_network() 
  let station = read_station() 

  return `${network}_${station}_.*/MSEED` // based on RingServer streamID format
}



// Function for creating local file store directory and files if it doesn't exists
async function createLocalFileStoreDir() {
  try {
    // Create /localDBs/ directory
    const localFileStoreDir = process.env.LOCALDBS_DIRECTORY
    try {
      await fs.promises.access(localFileStoreDir, fs.constants.R_OK);
      console.log(`./localDBs/ folder already exists`);
    } catch (error) {
      await fs.promises.mkdir(localFileStoreDir);
      console.log(`./localDBs/ folder created`);
    }

    // Create token.json if it doesn't exists
    try {
      await fs.promises.access(`${localFileStoreDir}/token.json`, fs.constants.R_OK);
      console.log(`token.json already exists.`);
    } catch (error) {
      const tokenJson = { accessToken: null, role: 'sensor' };
      await fs.promises.writeFile(`${localFileStoreDir}/token.json`, JSON.stringify(tokenJson));
      console.log(`token.json created.`);
    }


    // Create servers.json if it doesn't exists
    try {
      await fs.promises.access(`${localFileStoreDir}/servers.json`, fs.constants.R_OK);
      console.log(`servers.json already exists.`);
    } catch (error) {
      const serversJson = [];
      await fs.promises.writeFile(`${localFileStoreDir}/servers.json`, JSON.stringify(serversJson));
      console.log(`servers.json created.`);
    }

    // Create deviceInfo.json if it doesn't exists
    try {
      await fs.promises.access(`${localFileStoreDir}/deviceInfo.json`, fs.constants.R_OK);
      console.log(`deviceInfo.json already exists.`);
    } catch (error) {
      const deviceInfoJson = {
        deviceInfo: {
          network: null,
          station: null,
          location: null,
          channel: null,
          elevation: null,
          streamId: null,
        },
      };
      await fs.promises.writeFile(`${localFileStoreDir}/deviceInfo.json`, JSON.stringify(deviceInfoJson));
      console.log(`deviceInfo.json created.`);
    }
  } catch (error) {
    console.log(`${error}`)
  }
}

module.exports = {
  read_network,
  read_station,
  generate_streamId,
  createLocalFileStoreDir
};
