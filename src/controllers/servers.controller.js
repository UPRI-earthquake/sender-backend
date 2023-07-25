const fs = require('fs').promises;
const Joi = require('joi');
const streamController = require('./stream.controller')

async function getServersList(req, res) {
  try {
    const filePath = `${process.env.LOCALDBS_DIRECTORY}/servers.json`;
    const jsonString = await fs.readFile(filePath, 'utf-8');
    const data = JSON.parse(jsonString);
    
    console.log(data);
    res.status(200).json(data);
  } catch (err) {
    console.error(`Error reading servers.js: ${err}`);
    res.status(500).json({ status: 500, message: 'Error getting servers list' });
  }
}


const serverInputSchema = Joi.object().keys({
  hostName: Joi.string().required(),
  url: Joi.string().required(),
});

// Middleware function that checks if the device is already linked to an account
async function linkingStatusCheck(req, res, next) {
  // Read data from token.json file
  const filePath = `${process.env.LOCALDBS_DIRECTORY}/token.json`
  const jsonString = await fs.readFile(filePath, 'utf-8');
  const token = JSON.parse(jsonString);

  if (!token.accessToken) {
    return res.status(409).json({ status: 409, message: 'Link your device first before adding a ringserver url' })
  }

  next(); // Proceed to the next middleware/route handler
}

// Function for adding server to json array, adding server to streams object dictionary, and spawning childprocess
async function addServer(req, res) {
  try {
    const result = serverInputSchema.validate(req.body);
    if (result.error) {
      console.log(result.error.details[0].message);
      return res.status(400).json({ status: 400, message: result.error.details[0].message });
    }

    const filePath = `${process.env.LOCALDBS_DIRECTORY}/servers.json`;
    const jsonString = await fs.readFile(filePath, 'utf-8');
    const existingServers = JSON.parse(jsonString);

    const duplicate = existingServers.find((item) => item.url === req.body.url);
    if (duplicate) {
      return res.status(400).json({ status: 400, message: "Server URL already saved" });
    }

    const newServer = {
      hostName: req.body.hostName,
      url: req.body.url,
      isAllowedToStream: false,
    };

    existingServers.push(newServer);
    await fs.writeFile(filePath, JSON.stringify(existingServers)); // Write the input server to the array of servers in a json file (servers.json)

    await streamController.addNewStream(req.body.url, req.body.hostName); // A function from stream.controller which adds the newly added server to streams object dictionary
    await streamController.spawnSlink2dali(req.body.url); // Another function from stream.controller which spawns slink2dali childprocess that starts streaming to the specified ringserver

    console.log("Server added successfully");
    return res.status(200).json({ status: 200, message: "Server added successfully" });
  } catch (e) {
    console.log(`Error: ${e}`);
    return res.status(400).json({ status: 400, message: "Error occurred" });
  }
}

module.exports = { getServersList, addServer, linkingStatusCheck };
