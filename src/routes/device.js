const express = require('express');
const router = express.Router();
const bodyParser = require('body-parser')
const deviceController = require('../controllers/device.controller')

router.use(bodyParser.json())

/**
 * @swagger
 * /device/stream/start:
 *   post:
 *     summary: Endpoint to start slink2dali streaming to specified servers in the local file store
 *     tags:
 *       - Device
 *     responses:
 *       200:
 *         description: Successful spawning of slink2dali
 *       500:
 *         description: Internal server error
 */
router.post('/stream/start', 
  deviceController.streamStatusCheck, //Middleware function that checks if the device is already linked to an account; should not proceed if not yet linked.
  deviceController.startStreaming
)

/**
 * @swagger
 * /device/stream/status:
 *   get:
 *     summary: Endpoint for getting streaming status to each server
 *     tags:
 *       - Device
 *     responses:
 *       200:
 *         description: Successful response
 *       500:
 *         description: Internal server error
 */
router.get('/stream/status', deviceController.getStreamingStatus)

module.exports = router;
