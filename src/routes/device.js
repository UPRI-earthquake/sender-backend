const express = require('express');
const router = express.Router();
const fs = require('fs')
const path = require('path')
const bodyParser = require('body-parser')
const { getStreamsObject, spawnSlink2dali } = require('../controllers/stream.controller');

router.use(bodyParser.json())

let streamsObject = {};

// A function that returns streamsObject
async function populateStreamsObject() {
  try {
    streamsObject = await getStreamsObject();
    return streamsObject;
  } catch (error) {
    console.error(`Error getting streamsObject Dictionary: ${error}`);
  }
}

// Middleware function to check the streaming status to the specified server url; status should not be 'Streaming'
async function streamStatusCheck(req, res, next) {
  const url = req.body.url;
  if (!streamsObject.hasOwnProperty(url)) {
    return res.status(409).json({ message: 'Ringserver URL is invalid' })
  }

  if (streamsObject[url].status === 'Streaming') {
    return res.status(409).json({ message: `Device is already streaming to ${url}` })
  }

  next(); // Proceed to the next middleware/route handler
}

// TODO: Add middleware function that checks if the device is already linked to an account; should not proceed if not yet linked.
router.route('/stream/start').post(async (req, res, next) => {
  await populateStreamsObject();
  next();
}, streamStatusCheck,
  async (req, res) => {
    console.log('POST Request sent on /device/test endpoint')

    try {
      await spawnSlink2dali(req.body.url);
      res.status(200).json({ message: 'Child Process Spawned Successfully' });
    } catch (error) {
      console.log(`Error spawning slink2dali: ${error}`)
      res.status(500).json({ error: 'Error spawning child process' });
    }
  })


router.route('/stream/status').get(async (req, res) => {
  console.log('GET Request sent on /stream/status endpoint')
  streamsObject = await populateStreamsObject();

  const outputObject = {};

  for (const url in streamsObject) {
    if (streamsObject.hasOwnProperty(url)) {
      const { status, hostName } = streamsObject[url];
      outputObject[url] = { status, hostName };
    }
  }

  res.status(200).json({ message: 'Get Streams Status Success', payload: outputObject })
})

module.exports = router;
