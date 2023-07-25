const express = require('express');
const router = express.Router();
const fs = require('fs')
const path = require('path')
const bodyParser = require('body-parser')
const Joi = require('joi');
const { Result } = require('express-validator');
const serverController = require('../controllers/servers.controller.js')


router.use(bodyParser.json())

/**
 * @swagger
 * /servers/getList:
 *   get:
 *     summary: Endpoint for getting the list of servers saved in a JSON file
 *     tags:
 *       - Servers
 *     responses:
 *       200:
 *         description: Successful response with array of ringservers
 *       500:
 *         description: Internal server error
 */
router.get('/getList', serverController.getServersList);


/**
 * @swagger
 * /servers/add:
 *   post:
 *     summary: Endpoint for adding a ringserver to the list
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
 *         description: Successful response with array of ringservers
 *       409:
 *         description: Error - Device is not yet linked
 *       500:
 *         description: Internal server error
 */
router.post('/add', 
  serverController.linkingStatusCheck, // Middleware function
  serverController.addServer)

module.exports = router;
