const express = require('express');
const router = express.Router();
const fs = require('fs')
const path = require('path')
const bodyParser = require('body-parser')
const Joi = require('joi');
const { Result } = require('express-validator');
const { addNewStream, spawnSlink2dali } = require('../controllers/stream.controller.js')
const serversController = require('../controllers/servers.controller')


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
router.get('/getList', serversController.getServersList);


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

const serverInputSchema = Joi.object().keys({
    hostName: Joi.string().required(),
    url: Joi.string().required()
});

// Add middleware function that checks if the device is already linked to an account
async function linkingStatusCheck(req, res, next) {
  // Read data from token.json file
  const filePath = `${process.env.LOCALDBS_DIRECTORY}/token.json`
  const jsonString = await fs.promises.readFile(filePath, 'utf-8');
  const token = JSON.parse(jsonString);

  if (!token.accessToken) {
    return res.status(409).json({ message: 'Link your device first before adding a ringserver url' })
  }

  next(); // Proceed to the next middleware/route handler
}

// TODO: Add middleware function that checks if the device is already linked to an account; should not proceed adding server if not yet linked.
router.route('/add').post( linkingStatusCheck, async (req, res) => {
    try {
        const result = serverInputSchema.validate(req.body);
        if(result.error){
            console.log(result.error.details[0].message)
            res.status(400).json({ status: 400, message: result.error.details[0].message});
            return;
        }
        
        // Read data from servers.json file
        const filePath = `${process.env.LOCALDBS_DIRECTORY}/servers.json`
        const jsonString = await fs.promises.readFile(filePath, 'utf-8');
        const existingServers = JSON.parse(jsonString);
    
        // Create new server object to add to servers.json file
        const newServer = {
          hostName: req.body.hostName,
          url: req.body.url,
          isAllowedToStream: false
        };
    
        // Check if newServer already exists in existingServers
        const duplicate = existingServers.find(item => {
          return item.url === newServer.url;
        });
        if (duplicate) {
          return res.status(400).json({ message: "Server URL already saved" });
        }
    
        // Add newServer to existingServers array
        existingServers.push(newServer);
    
        // Write updated array to servers.json file
        await fs.promises.writeFile(filePath, JSON.stringify(existingServers));

        await addNewStream(req.body.url, req.body.hostName); // add entry to streamsObject dictionary on successful add server
        
        await spawnSlink2dali(req.body.url); // start streaming right after adding new server
        
        console.log("Server added succesfully")
        return res.status(200).json({ message: "Server added successfully" });
    
      } catch (e) {
        console.log(`Error: ${e}`);
        return res.status(400).json({ message: "Error occurred" });
      }
})

module.exports = router;
