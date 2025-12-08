const fs = require('fs')

function read_mac_address() {
  try {
    const mac_address = fs.readFileSync('/opt/settings/sys/eth-mac.txt', 'utf8');
    return mac_address.trim();
  } catch (error) {
    // log and move on
    console.log(error)
  }
  return '';
}

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

function read_coordinates() {
  const coordinates = { longitude: null, latitude: null, elevation: null };

  // Try parsing station.xml first (preferred source produced by RShake OS)
  try {
    const xml = fs.readFileSync('/opt/settings/station.xml', 'utf8');
    const lonMatch = xml.match(/<Longitude>\s*([-+]?\d+\.?\d*)\s*<\/Longitude>/i);
    const latMatch = xml.match(/<Latitude>\s*([-+]?\d+\.?\d*)\s*<\/Latitude>/i);
    const elevMatch = xml.match(/<Elevation>\s*([-+]?\d+\.?\d*)\s*<\/Elevation>/i);

    if (lonMatch) {
      const lon = parseFloat(lonMatch[1]);
      coordinates.longitude = Number.isNaN(lon) ? null : lon;
    }
    if (latMatch) {
      const lat = parseFloat(latMatch[1]);
      coordinates.latitude = Number.isNaN(lat) ? null : lat;
    }
    if (elevMatch) {
      const elev = parseFloat(elevMatch[1]);
      coordinates.elevation = Number.isNaN(elev) ? null : elev;
    }
  } catch (error) {
    console.log(error);
  }

  // Fall back to individual text files if present
  const fallbacks = [
    { key: 'longitude', path: '/opt/settings/sys/longitude.txt' },
    { key: 'latitude', path: '/opt/settings/sys/latitude.txt' },
    { key: 'elevation', path: '/opt/settings/sys/elevation.txt' },
  ];

  fallbacks.forEach(({ key, path }) => {
    try {
      if (coordinates[key] === null) {
        const value = fs.readFileSync(path, 'utf8').trim();
        const numeric = parseFloat(value);
        coordinates[key] = Number.isNaN(numeric) ? null : numeric;
      }
    } catch (error) {
      console.log(error);
    }
  });

  return coordinates;
}
// A function for getting the device streamId from rshake
function generate_streamId() {
  let network = read_network() 
  let station = read_station() 

  return `${network}_${station}_.*/MSEED` // based on RingServer streamID format
}

function getHostDeviceConfig() {
  const network = read_network();
  const station = read_station();
  const coords = read_coordinates();

  const streamId = (network && station) ? `${network}_${station}_.*/MSEED` : null;

  return {
    network: network || null,
    station: station || null,
    longitude: coords.longitude,
    latitude: coords.latitude,
    elevation: coords.elevation,
    streamId,
    source: 'rshake-config'
  };
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

    // Create linkCredentials.json if it doesn't exist
    try {
      await fs.promises.access(`${localFileStoreDir}/linkCredentials.json`, fs.constants.R_OK);
      console.log(`linkCredentials.json already exists.`);
    } catch (error) {
      const linkCredentials = {
        username: null,
        password: null,
        longitude: null,
        latitude: null,
        elevation: null,
        forceRelink: true,
      };
      await fs.promises.writeFile(`${localFileStoreDir}/linkCredentials.json`, JSON.stringify(linkCredentials));
      console.log(`linkCredentials.json created.`);
    }
  } catch (error) {
    console.log(`${error}`)
  }
}

module.exports = {
  read_mac_address,
  read_network,
  read_station,
  read_coordinates,
  generate_streamId,
  getHostDeviceConfig,
  createLocalFileStoreDir
};
