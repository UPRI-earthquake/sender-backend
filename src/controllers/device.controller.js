const fs = require('fs').promises;
const deviceService = require('../services/device.service')
const Joi = require('joi')
const { responseCodes, responseMessages } = require('./responseCodes')

// Function for getting the information of the device saved in local file store
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
    res.status(200).json({ 
      status: responseCodes.GET_DEVICE_INFO_SUCCESS,
      message: 'Get device information success', 
      payload: data.deviceInfo});
  } catch (error) {
    console.error(`Error reading file: ${error}`);
    res.status(500).json({ 
      status: responseCodes.GET_DEVICE_INFO_ERROR, 
      message: 'Error reading file' });
  }
}

// Function for linking the device to a registered account in ehub-backend
async function linkDevice(req, res) {
  // Input validation schema
  const accountValidationSchema = Joi.object({
    username: Joi.string().required(),
    password: Joi.string().pattern(new RegExp('^[a-zA-Z0-9]{6,30}$')).required(),
  });

  try {
    // Validate input
    const { error } = accountValidationSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ 
        status: responseCodes.DEVICE_LINKING_INVALID_INPUT, 
        message: error.details[0].message });
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
        status: responseCodes.DEVICE_LINKING_ERROR,
        message: error
      });
    }
  }
};


module.exports = { 
  getDeviceInfo, 
  linkDevice,
};