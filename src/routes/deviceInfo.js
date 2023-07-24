const express = require('express');
const router = express.Router();
const bodyParser = require('body-parser')
const deviceInfoController = require('../controllers/deviceInfo.controller')

router.use(bodyParser.json())


/**
 * @swagger
 * /deviceInfo:
 *   get:
 *     summary: Endpoint for reading device information from a JSON file
 *     tags:
 *       - Device
 *     responses:
 *       200:
 *         description: Successful response with device information
 *       500:
 *         description: Internal server error
 */
router.get('/', deviceInfoController.getDeviceInfo);

module.exports = router;