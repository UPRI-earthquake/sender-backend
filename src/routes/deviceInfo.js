const express = require('express');
const router = express.Router();
const fs = require('fs')
const path = require('path');
const bodyParser = require('body-parser')

router.use(bodyParser.json())


/**
 * @swagger
 * /deviceInfo:
 *   get:
 *     summary: Endpoint for reading device information from a JSON file
 *     tags:
 *       - Device
 *     responses:
 *       200:
 *         description: Successful response with device information
 *       500:
 *         description: Internal server error
 */
router.get('/', async (req, res) => {
  try {
    const filePath = `${process.env.LOCALDBS_DIRECTORY}/deviceInfo.json`

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

    const jsonString = await fs.promises.readFile(filePath, 'utf-8');
    data = JSON.parse(jsonString);

    console.log(data.deviceInfo);
    res.status(200).json(data.deviceInfo);
  } catch (error) {
    console.error(`Error reading file: ${error}`);
    res.status(500).json({message: 'Error reading file' });
  }
});

module.exports = router;