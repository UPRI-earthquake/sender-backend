const fs = require('fs').promises;
const Joi = require('joi');
const serversService = require('../services/servers.service')
const streamUtils = require('./stream.utils')
const deviceService = require('../services/device.service');
const { responseCodes, responseMessages } = require('./responseCodes')

// Function for getting the list of valid ringserver hosts registered in W1
async function getRingserverHosts(req, res) {
  try {
    const data = await serversService.requestRingserverHostsList();
    
    res.status(200).json({
      status: responseCodes.GET_SERVERS_LIST_SUCCESS,
      message: 'Get List of Ringserver Hosts Success', 
      payload: data });
  } catch (err) {
    console.error(`Error getRingserverHosts(): ${err}`);
    res.status(500).json({ 
      status: responseCodes.GET_SERVERS_LIST_SUCCESS,
      message: 'Error getting ringserver hosts' });
  }
}


// Middleware function that checks if the device is already linked to an account
async function linkingStatusCheck(req, res, next) {
  try {
    await deviceService.ensureValidAccessToken();
  } catch (error) {
    return res.status(409).json({ 
      status: responseCodes.ADD_SERVER_DEVICE_NOT_YET_LINKED, 
      message: 'Link your device first before adding a ringserver url' })
  }

  next(); // Proceed to the next middleware/route handler
}

// Function for adding server to json array, adding server to streams object dictionary, and spawning childprocess
async function addServer(req, res) {
  // No validation schema since this input is coming directly from W1, not a user input

  try {
    // Read list of servers from servers.json file
    const filePath = `${process.env.LOCALDBS_DIRECTORY}/servers.json`;
    const jsonString = await fs.readFile(filePath, 'utf-8');
    const existingServers = JSON.parse(jsonString);

    const duplicate = existingServers.find((item) => item.url === req.body.url);
    if (duplicate) {
      return res.status(401).json({ 
        status: responseCodes.ADD_SERVER_DUPLICATE,
        message: "Server URL already saved" });
    }

    const newServer = {
      institutionName: req.body.institutionName,
      url: req.body.url
    };

    existingServers.push(newServer);
    await fs.writeFile(filePath, JSON.stringify(existingServers)); // Add the input server to the array of servers in a json file (servers.json)

    await streamUtils.addNewStream(req.body.url, req.body.institutionName); // Adds the newly added server to streams object dictionary
    await streamUtils.spawnSlink2dali(req.body.url); // ASpawns slink2dali childprocess that starts streaming to the specified ringserver url

    console.log("Server added successfully");
    return res.status(200).json({ 
      status: responseCodes.ADD_SERVER_SUCCESS, 
      message: "Server added successfully" });
  } catch (e) {
    console.log(`Error: ${e}`);
    return res.status(500).json({ 
      status: responseCodes.ADD_SERVER_ERROR,
      message: "Error occurred in adding server" });
  }
}

module.exports = { getRingserverHosts, addServer, linkingStatusCheck };
