const express = require('express');
const router = express.Router();
const bodyParser = require('body-parser')
const deviceController = require('../controllers/device.controller')

router.use(bodyParser.json())


/**
 * @swagger
 * /device/info:
 *   get:
 *     summary: Read device information from a JSON file
 *     tags:
 *       - Device
 *     responses:
 *       200:
 *         description: Successful response with device information
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.GET_DEVICE_INFO_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Reading device information success"
 *                 payload:
 *                   definition: rshake device information
 *                   type: object
 *                   properties:
 *                     network:
 *                       type: string
 *                       example: AM
 *                     station: 
 *                       type: string
 *                       example: R3B2D
 *                     elevation:
 *                       type: number
 *                       example: 50
 *                     longitude:
 *                       type: number
 *                       example: 14.123
 *                     latitude:
 *                       type: number
 *                       example: 121.121
 *                     streamId:
 *                       type: string
 *                       example: AM_R3B2D.*\/MSEED
 *       500:
 *         description: Internal server error
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.GET_DEVICE_INFO_ERROR
 *                 message:
 *                   type: string
 *                   example: "Server error occured"
 */
router.get('/info', deviceController.getDeviceInfo);


/** 
 * @swagger
 * /device/link:
 *   post:
 *     summary: Link the rshake device to a registered account in earthquake-hub network
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
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.DEVICE_LINKING_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Device linking success"
 *       400:
 *         description: Error from earthquake-hub
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.DEVICE_LINKING_EHUB_ERROR
 *                 message: 
 *                   type: string
 *                   example: "Error from earthquake-hub: ..."
 *       401:
 *         description: Invalid inputs
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                 message: 
 *                   type: string
 *             examples:
 *               invalidUsernameInput:
 *                 value:
 *                   status: responseCodes.DEVICE_LINKING_INVALID_USERNAME
 *                   message: "Joi validation error: ..."
 *               invalidPasswordInput:
 *                 value:
 *                   status: responseCodes.DEVICE_LINKING_INVALID_PASSWORD
 *                   message: "Joi validation error: ..."
 *       500:
 *         description: Internal server error
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.DEVICE_LINKING_ERROR
 *                 message: 
 *                   type: string
 *                   example: "Device linking error"
 */
router.post('/link', deviceController.linkDevice)

// TODO: add swagger ui docs to this endpoint
router.post('/unlink', deviceController.unlinkDevice)

module.exports = router;