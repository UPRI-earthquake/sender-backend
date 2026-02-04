const fs = require('fs');
const path = require('path');

// Resolve the root of the RShake settings tree. On-device this is /opt/settings.
// In dev we fall back to the bundled fixtures at dev/settings (mirrors /opt/settings).
function resolveSettingsRoot() {
  const configured = process.env.RSHAKE_SETTINGS_PATH || '/opt/settings';
  if (fs.existsSync(configured)) {
    return configured;
  }

  const devFallback = path.resolve(__dirname, '../../dev/settings');
  if (fs.existsSync(devFallback)) {
    return devFallback;
  }

  return configured;
}

const settingsRoot = resolveSettingsRoot();
const settingsSysPath = `${settingsRoot}/sys`;
const settingsConfigPath = `${settingsRoot}/config`;

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

  // Preferred order: config/config.json (dataSharing), config/MD-info.json (GeoLocation),
  // station.xml (written by RShake OS), then legacy per-axis text files in sys/.
  const coerceNumber = (value) => {
    if (value === null || value === undefined || value === '') {
      return null;
    }
    const numeric = Number(value);
    return Number.isNaN(numeric) ? null : numeric;
  };

  const assignIfMissing = (key, value) => {
    if (coordinates[key] !== null && coordinates[key] !== undefined) {
      return;
    }
    const numeric = coerceNumber(value);
    if (numeric !== null) {
      coordinates[key] = numeric;
    }
  };

  const pickFromContainer = (container, keys) => {
    for (const key of keys) {
      if (container && Object.prototype.hasOwnProperty.call(container, key)) {
        const candidate = container[key];
        if (candidate !== null && candidate !== undefined && candidate !== '') {
          return candidate;
        }
      }
    }
    return null;
  };

  const configCandidates = [
    { path: `${settingsConfigPath}/config.json`, selector: (data) => data?.dataSharing || data },
    {
      path: `${settingsConfigPath}/MD-info.json`,
      selector: (data) => (
        data?.GeoLocation
        || data?.geoLocation
        || data?.location
        || data?.dataSharing
        || data?.data?.GeoLocation
        || data?.data?.geoLocation
        || data?.data?.location
        || data
      ),
    },
  ];

  for (const source of configCandidates) {
    try {
      if (!fs.existsSync(source.path)) {
        continue;
      }

      const contents = fs.readFileSync(source.path, 'utf8');
      const parsed = JSON.parse(contents);
      const container = source.selector ? source.selector(parsed) : parsed;

      assignIfMissing('longitude', pickFromContainer(container, ['lon', 'longitude', 'lng', 'long']));
      assignIfMissing('latitude', pickFromContainer(container, ['lat', 'latitude']));
      assignIfMissing('elevation', pickFromContainer(container, ['elevation', 'elev', 'altitude', 'alt']));

      if (coordinates.longitude !== null && coordinates.latitude !== null && coordinates.elevation !== null) {
        break;
      }
    } catch (error) {
      console.log(error);
    }
  }

  // Try parsing station.xml first (preferred source produced by RShake OS)
  const stationXmlCandidates = [
    `${settingsRoot}/station.xml`,
    `${settingsSysPath}/station.xml`,
  ];

  for (const xmlPath of stationXmlCandidates) {
    try {
      if (!fs.existsSync(xmlPath)) {
        continue;
      }

	      const xml = fs.readFileSync(xmlPath, 'utf8');
	      // XML tags are case-sensitive, but station.xml casing varies across releases/devices.
	      // Use a case-insensitive match to tolerate those differences.
	      const lonMatch = xml.match(/<Longitude>\s*([-+]?\d+\.?\d*)\s*<\/Longitude>/i);
	      const latMatch = xml.match(/<Latitude>\s*([-+]?\d+\.?\d*)\s*<\/Latitude>/i);
	      const elevMatch = xml.match(/<Elevation>\s*([-+]?\d+\.?\d*)\s*<\/Elevation>/i);

      if (lonMatch) {
        assignIfMissing('longitude', parseFloat(lonMatch[1]));
      }
      if (latMatch) {
        assignIfMissing('latitude', parseFloat(latMatch[1]));
      }
      if (elevMatch) {
        assignIfMissing('elevation', parseFloat(elevMatch[1]));
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
      if (coordinates[key] === null && fs.existsSync(path)) {
        const value = fs.readFileSync(path, 'utf8').trim();
        assignIfMissing(key, value);
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
	        const code = error?.code ? `${error.code} ` : '';
	        console.log(`Unable to prepare local store directory "${dir}": ${code}${error?.message || error}`);
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
