const fs = require('fs').promises;
const streamController = require('./stream.controller')


let streamsObject = {};

// Middleware function that checks if the device is already linked to an account; Status should not be 'Streaming'. Should not proceed if 'Not yet linked'.
async function streamStatusCheck(req, res, next) {
  await streamController.getStreamsObject();

  const url = req.body.url;
  if (!streamsObject.hasOwnProperty(url)) {
    return res.status(409).json({ message: 'Ringserver URL is invalid' })
  }

  if (streamsObject[url].status === 'Streaming') {
    return res.status(409).json({ message: `Device is already streaming to ${url}` })
  }

  next(); // Proceed to the next middleware/route handler
}

async function startStreaming(req, res) {
  console.log('POST Request sent on /stream/start endpoint')

  try {
    await spawnSlink2dali(req.body.url);
    res.status(200).json({ message: 'Child Process Spawned Successfully' });
  } catch (error) {
    console.log(`Error spawning slink2dali: ${error}`)
    res.status(500).json({ error: 'Error spawning child process' });
  }
}

async function getStreamingStatus(req, res) {
  console.log('GET Request sent on /stream/status endpoint')
  streamsObject = await streamController.getStreamsObject();

  const outputObject = {};

  for (const url in streamsObject) {
    if (streamsObject.hasOwnProperty(url)) {
      const { status, hostName, retryCount } = streamsObject[url];
      outputObject[url] = { status, hostName, retryCount };
    }
  }

  res.status(200).json({ message: 'Get Streams Status Success', payload: outputObject })
}

module.exports = { getStreamingStatus, streamStatusCheck, startStreaming };
