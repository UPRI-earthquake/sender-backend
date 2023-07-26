const fs = require('fs').promises;
const deviceService = require('../services/device.service')
const Joi = require('joi')


async function getDeviceInfo(req, res) {
  try {
    const filePath = `${process.env.LOCALDBS_DIRECTORY}/deviceInfo.json`;
    const defaultDeviceInfo = {
      network: null,
      station: null,
      location: null,
      channel: null,
      elevation: null,
      streamId: null,
    };

    let data = { deviceInfo: defaultDeviceInfo };

    const jsonString = await fs.readFile(filePath, 'utf-8');
    data = JSON.parse(jsonString);

    console.log(data.deviceInfo);
    res.status(200).json(data.deviceInfo);
  } catch (error) {
    console.error(`Error reading file: ${error}`);
    res.status(500).json({ message: 'Error reading file' });
  }
}


const accountValidationSchema = Joi.object({
  username: Joi.string().required(),
  password: Joi.string().pattern(new RegExp('^[a-zA-Z0-9]{6,30}$')).required(),
});

async function linkDevice(req, res) {
  try {
    // Validate input
    const { error } = accountValidationSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ status: 400, message: error.details[0].message });
    }

    let token = await deviceService.checkAuthToken(); // Check auth token from file
    if (!token) {
      token = await deviceService.requestAuthToken(req.body.username, req.body.password) // Request accessToken in ehub-backend
    }

    // Link the device and get device information
    const deviceInfo = await deviceService.requestLinking(token);
    const deviceInfoPath = `${process.env.LOCALDBS_DIRECTORY}/deviceInfo.json`;
    await fs.writeFile(deviceInfoPath, JSON.stringify(deviceInfo));

    return res.status(200).json({
      status: 200,
      message: 'Successfully Requested Linking to W1',
    });
  } catch (error) {
    // TODO: Add clean-up function that restores local file stores if an error is encountered while linking
    if (error.response) {
      return res.status(error.response.status).json({
        status: error.response.status,
        message: "Error from earthquake-hub: " + error.response.data.message,
      });
    } else {
      console.log(error)
      return res.status(500).json({
        status: 500,
        message: error
      });
    }
  }
};


module.exports = { 
  getDeviceInfo, 
  linkDevice,
};