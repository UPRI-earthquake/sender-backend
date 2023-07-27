const fs = require('fs').promises;
const Joi = require('joi');
const streamUtils = require('./stream.utils')
const { responseCodes, responseMessages } = require('./responseCodes')

// Function for reading the list of ringservers added in the local file store
async function getServersList(req, res) {
  try {
    const filePath = `${process.env.LOCALDBS_DIRECTORY}/servers.json`;
    const jsonString = await fs.readFile(filePath, 'utf-8');
    const data = JSON.parse(jsonString);
    
    console.log(data);
    res.status(200).json({
      status: responseCodes.GET_SERVERS_LIST_SUCCESS,
      message: 'Get Servers List Success', 
      payload: data });
  } catch (err) {
    console.error(`Error reading servers.js: ${err}`);
    res.status(500).json({ 
      status: responseCodes.GET_SERVERS_LIST_SUCCESS,
      message: 'Error getting servers list' });
  }
}


// Middleware function that checks if the device is already linked to an account
async function linkingStatusCheck(req, res, next) {
  // Read data from token.json file
  const filePath = `${process.env.LOCALDBS_DIRECTORY}/token.json`
  const jsonString = await fs.readFile(filePath, 'utf-8');
  const token = JSON.parse(jsonString);

  if (!token.accessToken) {
    return res.status(409).json({ 
      status: responseCodes.ADD_SERVER_DEVICE_NOT_YET_LINKED, 
      message: 'Link your device first before adding a ringserver url' })
  }

  next(); // Proceed to the next middleware/route handler
}

// Function for adding server to json array, adding server to streams object dictionary, and spawning childprocess
async function addServer(req, res) {
  // Input validation schema
  const serverInputSchema = Joi.object().keys({
    hostName: Joi.string().required(),
    url: Joi.string().regex(/^(https?:\/\/)?([a-zA-Z0-9.-]+)(\.[a-z]{2,6})?(:[0-9]{2,5})?(\/[^\\s]*)?$/),
  });
  
  try {
    const result = serverInputSchema.validate(req.body);
    if (result.error) {
      console.log(result.error.details[0].message);
      return res.status(400).json({ 
        status: responseCodes.ADD_SERVER_INVALID_INPUT, 
        message: result.error.details[0].message });
    }

    const filePath = `${process.env.LOCALDBS_DIRECTORY}/servers.json`;
    const jsonString = await fs.readFile(filePath, 'utf-8');
    const existingServers = JSON.parse(jsonString);

    const duplicate = existingServers.find((item) => item.url === req.body.url);
    if (duplicate) {
      return res.status(400).json({ 
        status: responseCodes.ADD_SERVER_DUPLICATE,
         message: "Server URL already saved" });
    }

    const newServer = {
      hostName: req.body.hostName,
      url: req.body.url,
      isAllowedToStream: false,
    };

    existingServers.push(newServer);
    await fs.writeFile(filePath, JSON.stringify(existingServers)); // Write the input server to the array of servers in a json file (servers.json)

    await streamUtils.addNewStream(req.body.url, req.body.hostName); // A function from stream.controller which adds the newly added server to streams object dictionary
    await streamUtils.spawnSlink2dali(req.body.url); // Another function from stream.controller which spawns slink2dali childprocess that starts streaming to the specified ringserver

    console.log("Server added successfully");
    return res.status(200).json({ 
      status: responseCodes.ADD_SERVER_SUCCESS, 
      message: "Server added successfully" });
  } catch (e) {
    console.log(`Error: ${e}`);
    return res.status(400).json({ 
      status: responseCodes.ADD_SERVER_ERROR,
      message: "Error occurred in adding server" });
  }
}

module.exports = { getServersList, addServer, linkingStatusCheck };
