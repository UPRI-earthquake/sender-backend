const express = require('express');
const router = express.Router();
const bodyParser = require('body-parser')
const deviceController = require('../controllers/device.controller')

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
router.get('/info', deviceController.getDeviceInfo);


/** 
 * @swagger
 * /deviceLinkRequest:
 *   post:
 *     summary: Endpoint for linking the device to a registered account in earthquake-hub network (this endpoint is dependent to earthquake-hub-backend, meaning to test this endpoint make sure that ehub-backend container is up)
 *     tags:
 *       - Device
 *     requestBody:
 *       description: User credentials registered in earthquake-hub network
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               username:
 *                 type: string
 *                 description: Username registered in earthquake-hub network
 *               password:
 *                 type: string
 *                 description: Account's password
 *             example:
 *               username: citizen
 *               password: testpassword
 *     responses:
 *       200:
 *         description: Successful response with device information
 *       400:
 *         description: Device already linked to an existing account
 *       500:
 *         description: Internal server error
 */
router.post('/link', deviceController.linkDevice)

module.exports = router;