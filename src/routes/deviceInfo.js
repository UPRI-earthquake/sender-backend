const express = require('express');
const router = express.Router();
const fs = require('fs')
const bodyParser = require('body-parser')

router.use(bodyParser.json())

router.get('/', async (req, res) => {
  try {
    const filePath = 'src/localDBs/deviceInfo.json';

      let data = {
          "deviceInfo": {
              "network": null,
              "station": null,
              "location": null,
              "channel": null,
              "elevation": null,
              "streamId": null
          }
      };

    try {
      const jsonString = await fs.promises.readFile(filePath, 'utf-8');
      data = JSON.parse(jsonString);
    } catch (error) {
      // File does not exist, create it
      await fs.promises.writeFile(filePath, JSON.stringify(data), 'utf-8');
    }

    console.log(data.deviceInfo);
    res.status(200).json(data.deviceInfo);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

module.exports = router;