const express = require('express');
const router = express.Router();
const bodyParser = require('body-parser')
const streamController = require('../controllers/stream.controller')

router.use(bodyParser.json())

/**
 * @swagger
 * /stream/start:
 *   post:
 *     summary: Start slink2dali streaming to specified servers in the local file store
 *     tags:
 *       - Stream
 *     responses:
 *       200:
 *         description: Successful spawning of slink2dali
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.START_STREAMING_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Child Process Spawned Successfully"
 *       400:
 *         description: Ringserver url is not saved to local file store
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.START_STREAMING_INVALID_URL
 *                 message:
 *                   type: string
 *                   example: "Ringserver URL is not included in the local file store"
 *       401:
 *         description: Device is already streaming to the specified ringserver url
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.START_STREAMING_DUPLICATE
 *                 message:
 *                   type: string
 *                   example: "Device is already streaming"
 *       500:
 *         description: Internal server error
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.START_STREAMING_ERROR
 *                 message:
 *                   type: string
 *                   example: "Error spawning child process"
 */
router.post('/start', 
  streamController.streamStatusCheck, //Middleware function that checks if the device is already linked to an account; should not proceed if not yet linked.
  streamController.startStreaming
)

/**
 * @swagger
 * /stream/status:
 *   get:
 *     summary: Get streaming status to each server
 *     tags:
 *       - Stream
 *     responses:
 *       200:
 *         description: Successful response
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.GET_STREAMS_STATUS_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Get Streams Status Success"
 *                 payload:
 *                   description: List of ringserver url
 *                   type: object
 *                   properties:
 *                     Ringserver's url:
 *                       type: object
 *                       properties:
 *                         status:
 *                           type: string
 *                           example: "Connecting"
 *                           description: >
 *                             Streaming status of the device to the specified ringserver:
 *                              * `Not Streaming` - when device is newly added
 *                              * `Connecting`    - when device is unsuccessful in connecting to ringserver up to 3 times (reconnection interval is every 30 seconds)
 *                              * `Streaming`     - when device can successfully write to ringserver
 *                              * `Error`         - when device is unsuccessful in connecting to ringserver for more than 3 times (will still try to reconnect every 2 minutes)
 *                         hostName:
 *                           type: string
 *                           example: "UPRI's Ringserver"
 *                         retryCount:
 *                           type: number
 *                           example: 0
 */
router.get('/status', streamController.getStreamingStatus)

module.exports = router;
