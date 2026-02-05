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
 *                   example: "Get device information success"
 *                 payload:
 *                   description: RShake device information + link/token status
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
 *                       example: 121.121
 *                     latitude:
 *                       type: number
 *                       example: 14.123
 *                     streamId:
 *                       type: string
 *                       example: AM_R3B2D.*\/MSEED
 *                     linked:
 *                       type: boolean
 *                       description: True when an access token and streamId are present in local state.
 *                       example: true
 *                     hostConfig:
 *                       type: object
 *                       description: Metadata read from the host /opt/settings tree (or dev fixtures).
 *                       properties:
 *                         network:
 *                           type: string
 *                           nullable: true
 *                         station:
 *                           type: string
 *                           nullable: true
 *                         elevation:
 *                           type: number
 *                           nullable: true
 *                         longitude:
 *                           type: number
 *                           nullable: true
 *                         latitude:
 *                           type: number
 *                           nullable: true
 *                         streamId:
 *                           type: string
 *                           nullable: true
 *                         source:
 *                           type: string
 *                           example: rshake-config
 *                     tokenStatus:
 *                       type: object
 *                       description: Access token health summary (decoded JWT expiry when available).
 *                       properties:
 *                         state:
 *                           type: string
 *                           example: valid
 *                         reason:
 *                           type: string
 *                           nullable: true
 *                         expiresAt:
 *                           type: number
 *                           nullable: true
 *                           description: JWT exp (unix seconds) when available
 *                         secondsToExpiry:
 *                           type: number
 *                           nullable: true
 *                         expiringSoon:
 *                           type: boolean
 *                           nullable: true
 *                         accessTokenPresent:
 *                           type: boolean
 *                           nullable: true
 *                         checkedAt:
 *                           type: number
 *                           description: Unix seconds when status was computed
 *                         details:
 *                           type: string
 *                           nullable: true
 *                     refreshTokenStatus:
 *                       type: object
 *                       description: Refresh token health summary (decoded JWT expiry when available).
 *                       properties:
 *                         state:
 *                           type: string
 *                           example: valid
 *                         reason:
 *                           type: string
 *                           nullable: true
 *                         expiresAt:
 *                           type: number
 *                           nullable: true
 *                         secondsToExpiry:
 *                           type: number
 *                           nullable: true
 *                         expiringSoon:
 *                           type: boolean
 *                           nullable: true
 *                         refreshTokenPresent:
 *                           type: boolean
 *                           nullable: true
 *                         checkedAt:
 *                           type: number
 *                         details:
 *                           type: string
 *                           nullable: true
 *                     linkState:
 *                       type: string
 *                       description: Remote link status from W1 when available.
 *                       enum: [linked, unlinked, notLinked, unknown]
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
 *                   example: "Reading device information error"
 */
router.get('/info', deviceController.getDeviceInfo);

/**
 * @swagger
 * /device/config/refresh:
 *   post:
 *     summary: Refresh stored device metadata from the Raspberry Shake configuration files
 *     tags:
 *       - Device
 *     responses:
 *       200:
 *         description: Successfully refreshed metadata from the host config
 *       400:
 *         description: Host config missing or incomplete
 *       500:
 *         description: Internal server error
 */
router.post('/config/refresh', deviceController.refreshHostMetadata);


/** 
 * @swagger
 * /device/link:
 *   post:
 *     summary: Add the rshake device information to W1 database and link it to a registered account in earthquake-hub network
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
 *               latitude:
 *                 type: string
 *                 description: Device location (in degree coordinates)
 *               longitude:
 *                 type: string
 *                 description: Device location (in degree coordinates)
 *               elevation:
 *                 type: string
 *                 description: Device's elevation relative to sea level 
 *             example:
 *               username: "citizen"
 *               password: "testpassword"
 *               latitude: "20"
 *               longitude: "20"
 *               elevation: "0"
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
 *               invalidLatitudeInput:
 *                 value:
 *                   status: responseCodes.DEVICE_LINKING_INVALID_LATITUDE_VALUE
 *                   message: "Joi validation error: ..."
 *               invalidLongitudeInput:
 *                 value:
 *                   status: responseCodes.DEVICE_LINKING_INVALID_LONGITUDE_VALUE
 *                   message: "Joi validation error: ..."
 *               invalidElevationInput:
 *                 value:
 *                   status: responseCodes.DEVICE_LINKING_INVALID_ELEVATION_VALUE
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

/** 
 * @swagger
 * /device/unlink:
 *   post:
 *     summary: Unlink the device from the registered account in earthquake-hub network
 *     tags:
 *       - Device
 *     responses:
 *       200:
 *         description: Successful unlinking of device
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.DEVICE_UNLINKING_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Successfully Requested Unlinking to W1"
 *       500:
 *         description: Internal server error
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.DEVICE_UNLINKING_ERROR
 *                 message: 
 *                   type: string
 *                   example: "Obj.error"
 */
router.post('/unlink', deviceController.unlinkDevice)

/**
 * @swagger
 * /device/reset-link:
 *   post:
 *     summary: Reset local state and remove the device record from Earthquake Hub
 *     tags:
 *       - Device
 *     responses:
 *       200:
 *         description: Device reset request succeeded
 *       500:
 *         description: Reset failed
 */
router.post('/reset-link', deviceController.resetLinkState)

/**
 * @swagger
 * /device/refresh-token:
 *   post:
 *     summary: Force an access-token refresh using the locally stored refresh token
 *     description: Bypasses the proactive refresh scheduler and immediately attempts a refresh against W1.
 *     tags:
 *       - Device
 *     responses:
 *       200:
 *         description: Access token refreshed
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.DEVICE_TOKEN_REFRESH_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Access token refreshed"
 *                 payload:
 *                   type: object
 *                   properties:
 *                     tokenStatus:
 *                       type: object
 *                     refreshTokenStatus:
 *                       type: object
 *       409:
 *         description: Refresh token missing/expired; relinking required
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.DEVICE_RELINK_REQUIRED
 *                 message:
 *                   type: string
 *                   example: "Refresh token unavailable. Relink the device to continue streaming."
 *                 payload:
 *                   type: object
 *                   properties:
 *                     refreshTokenStatus:
 *                       type: object
 *       500:
 *         description: Unable to refresh access token
 */
router.post('/refresh-token', deviceController.refreshAccessToken)

module.exports = router;
