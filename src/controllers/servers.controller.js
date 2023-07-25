const fs = require('fs').promises;
const Joi = require('joi');
const { addNewStream, spawnSlink2dali } = require('./stream.controller')

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
      return res.status(400).json({ message: "Server URL already saved" });
    }

    const newServer = {
      hostName: req.body.hostName,
      url: req.body.url,
      isAllowedToStream: false,
    };

    existingServers.push(newServer);
    await fs.writeFile(filePath, JSON.stringify(existingServers)); // Write the input server to the array of servers in a json file (servers.json)

    await addNewStream(req.body.url, req.body.hostName); // A function from stream.controller which adds the newly added server to streams object dictionary
    await spawnSlink2dali(req.body.url); // Another function from stream.controller which spawns slink2dali childprocess that starts streaming to the specified ringserver

    console.log("Server added successfully");
    return res.status(200).json({ status: 200, message: "Server added successfully" });
  } catch (e) {
    console.log(`Error: ${e}`);
    return res.status(400).json({ status: 400, message: "Error occurred" });
  }
}

module.exports = { getServersList, addServer };
