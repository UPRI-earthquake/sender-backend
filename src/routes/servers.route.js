const express = require('express');
const router = express.Router();
const bodyParser = require('body-parser')
const serverController = require('../controllers/servers.controller.js')


router.use(bodyParser.json())

/**
 * @swagger
 * /servers/getList:
 *   get:
 *     summary: Read list of servers saved in a JSON file
 *     tags:
 *       - Servers
 *     responses:
 *       200:
 *         description: Successful response with array of ringservers
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.GET_SERVERS_LIST_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Get Servers List Success"
 *                 payload:
 *                   definition: Array of ringservers object saved in json file
 *                   type: array
 *                   items:
 *                     type: object
 *                     properties:
 *                       hostName:
 *                         type: string
 *                         example: "UPRI's Ringserver"
 *                       url:
 *                         type: string
 *                         example: "https://earthquake.science.upd.edu.ph"
 *       500:
 *         description: Error reading servers.json
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.GET_SERVERS_LIST_ERROR
 *                 message:
 *                   type: string
 *                   example: "Error getting servers list"
 */
router.get('/getList', serverController.getServersList);


/**
 * @swagger
 * /servers/add:
 *   post:
 *     summary: Add a ringserver to the list
 *     tags:
 *       - Servers
 *     requestBody:
 *       description: Supplied here is a valid ringserver url
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               url:
 *                 type: string
 *                 description: Ringserver URL (must be a valid url format)
 *               hostName:
 *                 type: string
 *                 description: Ringserver's alias
 *             example:
 *               url: https://earthquake.science.upd.edu.ph
 *               hostName: UPRI's Ringserver
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
 *                   example: responseCodes.ADD_SERVER_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Server added successfully"
 *       400:
 *         description: Input validation error
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
  *               invalidHostName:
  *                 value:
  *                   status: responseCodes.ADD_SERVER_INVALID_HOSTNAME
  *                   message: "Joi validation error: ..."
  *               invalidUrl:
  *                 value:
  *                   status: responseCodes.ADD_SERVER_INVALID_URL
  *                   message: "Joi validation error: ..."
 *       401:
 *         description: Server input is already saved
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.ADD_SERVER_DUPLICATE
 *                 message:
 *                   type: string
 *                   example: "Server URL already saved"
 *       500:
 *         description: Internal server error
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.ADD_SERVER_ERROR
 *                 message:
 *                   type: string
 *                   example: "Error occurred in adding server"
 */
router.post('/add', 
  serverController.linkingStatusCheck, // Middleware function
  serverController.addServer)

module.exports = router;
