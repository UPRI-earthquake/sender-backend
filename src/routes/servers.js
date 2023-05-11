const express = require('express');
const router = express.Router();
const fs = require('fs')
const bodyParser = require('body-parser')
const Joi = require('joi');
const { Result } = require('express-validator');

router.use(bodyParser.json())

router.route('/getList').get(
    (req, res) => {
        // Read the local file store
        fs.readFile('src/localDBs/servers.json', 'utf-8', function (err, jsonString) {
            const data = JSON.parse(jsonString);
            console.log(data)
            res.json(data)
        })
    }
)


const serverInputSchema = Joi.object().keys({
    hostName: Joi.string().required(),
    url: Joi.string().uri().required()
});

router.route('/add').post(async (req, res) => {
    try {
        const result = serverInputSchema.validate(req.body);
        if(result.error){
            console.log(result.error.details[0].message)
            res.status(400).json({ status: 400, message: result.error.details[0].message});
            return;
        }
        
        // Read data from servers.json file
        const jsonString = await fs.promises.readFile('src/localDBs/servers.json', 'utf-8');
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
        await fs.promises.writeFile("src/localDBs/servers.json", JSON.stringify(existingServers));
    
        console.log("Server added succesfully")
        return res.status(200).json({ message: "Server added successfully" });
    
      } catch (e) {
        console.log(`Error: ${e}`);
        return res.status(400).json({ message: "Error occurred" });
      }
})

module.exports = router;