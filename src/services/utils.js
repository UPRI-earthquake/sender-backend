const fs = require('fs');

const settingsRoot = process.env.RSHAKE_SETTINGS_PATH || '/opt/settings';
const settingsSysPath = `${settingsRoot}/sys`;

function read_mac_address() {
  try {
    const mac_address = fs.readFileSync(`${settingsSysPath}/eth-mac.txt`, 'utf8');
    return mac_address.trim();
  } catch (error) {
    console.log(error);
  }
  return '';
}

function read_network() {
  try {
    const network = fs.readFileSync(`${settingsSysPath}/NET.txt`, 'utf8');
    return network.trim();
  } catch (error) {
    console.log(error);
  }
  return '';
}

function read_station() {
  try {
    const station = fs.readFileSync(`${settingsSysPath}/STN.txt`, 'utf8');
    return station.trim();
  } catch (error) {
    console.log(error);
  }
  return '';
}

function read_coordinates() {
  const coordinates = { longitude: null, latitude: null, elevation: null };

  // Try parsing station.xml first (preferred source produced by RShake OS)
  const stationXmlCandidates = [
    `${settingsRoot}/station.xml`,
    `${settingsSysPath}/station.xml`,
  ];

  for (const xmlPath of stationXmlCandidates) {
    try {
      const xml = fs.readFileSync(xmlPath, 'utf8');
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

      break; // Stop after first readable station.xml
    } catch (error) {
      console.log(error);
    }
  }

  // Fall back to individual text files if present
  const fallbacks = [
    { key: 'longitude', path: `${settingsSysPath}/longitude.txt` },
    { key: 'latitude', path: `${settingsSysPath}/latitude.txt` },
    { key: 'elevation', path: `${settingsSysPath}/elevation.txt` },
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
    // Try to prepare the configured directory; fall back to ./localDBs when running outside Docker.
    const ensureDir = async (dir) => {
      try {
        await fs.promises.mkdir(dir, { recursive: true });
        await fs.promises.access(dir, fs.constants.R_OK | fs.constants.W_OK);
        return dir;
      } catch (error) {
        console.log(error);
        return null;
      }
    };

    const configuredDir = process.env.LOCALDBS_DIRECTORY || './localDBs';
    let localFileStoreDir = await ensureDir(configuredDir);

    if (!localFileStoreDir && configuredDir !== './localDBs') {
      const fallbackDir = './localDBs';
      localFileStoreDir = await ensureDir(fallbackDir);
      if (localFileStoreDir) {
        process.env.LOCALDBS_DIRECTORY = fallbackDir;
        console.log(`LOCALDBS_DIRECTORY fallback to ${fallbackDir}`);
      }
    }

    if (!localFileStoreDir) {
      throw new Error(`Unable to prepare local file store directory: ${configuredDir}`);
    }

    // Create /localDBs/ directory
    console.log(`Using localDBs directory: ${localFileStoreDir}`);

    // Create token.json if it doesn't exists
    try {
      await fs.promises.access(`${localFileStoreDir}/token.json`, fs.constants.R_OK);
      console.log(`token.json already exists.`);
    } catch (error) {
      const tokenJson = {
        accessToken: null,
        refreshToken: null,
        accessTokenExpiresAt: null,
        refreshTokenExpiresAt: null,
        role: 'sensor',
      };
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
  read_mac_address,
  read_network,
  read_station,
  read_coordinates,
  generate_streamId,
  getHostDeviceConfig,
  createLocalFileStoreDir
};
