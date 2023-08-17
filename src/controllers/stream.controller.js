const streamUtils = require('./stream.utils')
const { responseCodes, responseMessages } = require('./responseCodes')


let streamsObject = {};

// Middleware function that checks if the device is already linked to an account; Status should not be 'Streaming'. Should not proceed if 'Not yet linked'.
async function streamStatusCheck(req, res, next) {
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
    await spawnSlink2dali(req.body.url);
    res.status(200).json({ 
      status: responseCodes.START_STREAMING_SUCCESS,
      message: 'Child Process Spawned Successfully' });
  } catch (error) {
    console.log(`Error spawning slink2dali: ${error}`)
    res.status(500).json({ 
      status: responseCodes.START_STREAMING_ERROR,
      message: 'Error spawning child process' });
  }
}

// Function for getting the status of each stream to ringservers 
async function getStreamingStatus(req, res) {
  console.log('GET Request sent on /stream/status endpoint')
  streamsObject = await streamUtils.getStreamsObject();

  const outputObject = {};

  for (const url in streamsObject) {
    if (streamsObject.hasOwnProperty(url)) {
      const { status, hostName, retryCount } = streamsObject[url];
      outputObject[url] = { status, hostName, retryCount };
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
