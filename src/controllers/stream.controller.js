const streamUtils = require('./stream.utils');
let { streamsObject } = require('./stream.utils');
const deviceService = require('../services/device.service');
const { responseCodes, responseMessages } = require('./responseCodes');


// Middleware function that checks if the device is already linked to an account; Status should not be 'Streaming'. Should not proceed if 'Not yet linked'.
async function streamStatusCheck(req, res, next) {
  await streamUtils.reconcileStreamsWithFile();
  await streamUtils.getStreamsObject();

  const url = req.body.url;
  if (!streamsObject.hasOwnProperty(url)) {
    return res.status(400).json({ 
      status: responseCodes.START_STREAMING_INVALID_URL,
      message: 'Ringserver URL is not included in the local file store' })
  }

  if (streamsObject[url].status === 'Streaming') {
    return res.status(401).json({ 
      status: responseCodes.START_STREAMING_DUPLICATE,
      message: `Device is already streaming to ${url}` })
  }

  next(); // Proceed to the next middleware/route handler
}

// Function for spawning slink2dali child process
async function startStreaming(req, res) {
  console.log('POST Request sent on /stream/start endpoint')

  try {
    await deviceService.ensureValidAccessToken();
    await streamUtils.spawnSlink2dali(req.body.url);
    res.status(200).json({ 
      status: responseCodes.START_STREAMING_SUCCESS,
      message: 'Child Process Spawned Successfully' });
  } catch (error) {
    console.log(`Error spawning slink2dali: ${error}`)
    const relinkRequired = error?.code === 'RELINK_REQUIRED';
    res.status(relinkRequired ? 409 : 500).json({ 
      status: relinkRequired
        ? responseCodes.DEVICE_RELINK_REQUIRED
        : responseCodes.START_STREAMING_ERROR,
      message: relinkRequired
        ? (error.message || 'Device link expired. Relink the device to resume streaming.')
        : 'Error spawning child process' });
  }
}

// Function for getting the status of each stream to ringservers 
async function getStreamingStatus(req, res) {
  console.log('GET Request sent on /stream/status endpoint')
  await streamUtils.reconcileStreamsWithFile();
  streamsObject = await streamUtils.getStreamsObject();

  const outputObject = {};

  for (const url in streamsObject) {
    if (streamsObject.hasOwnProperty(url)) {
      const { status, institutionName, retryCount, logs } = streamsObject[url];
      outputObject[url] = { status, institutionName, retryCount, logs: logs || [] };
    }
  }

  res.status(200).json({ 
    status: responseCodes.GET_STREAMS_STATUS_SUCCESS,
    message: 'Get Streams Status Success', 
    payload: outputObject })
}

module.exports = { 
  streamStatusCheck,
  startStreaming,
  getStreamingStatus
};
