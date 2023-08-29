const fs = require('fs').promises;
const deviceService = require('../services/device.service')
const streamUtils = require('./stream.utils')
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

    // console.log(data.deviceInfo);
    res.status(200).json({ 
      status: responseCodes.GET_DEVICE_INFO_SUCCESS,
      message: 'Get device information success', 
      payload: data.deviceInfo});
  } catch (error) {
    console.error(`Error reading file: ${error}`);
    res.status(500).json({ 
      status: responseCodes.GET_DEVICE_INFO_ERROR, 
      message: 'Reading device information error' });
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
    const result = accountValidationSchema.validate(req.body);
    if (result.error) {
      const errorMessage = result.error.details[0].message;
      console.log(errorMessage);

      let statusCode = null;
      if (errorMessage.includes('username') ) {
        statusCode = responseCodes.DEVICE_LINKING_INVALID_USERNAME
      } 
      else if (errorMessage.includes('password')) {
        statusCode = responseCodes.DEVICE_LINKING_INVALID_PASSWORD
      } 

      return res.status(401).json({ 
        status: statusCode, 
        message: `Joi validation error: ${errorMessage}` });
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
      status: responseCodes.DEVICE_LINKING_SUCCESS,
      message: 'Successfully Requested Linking to W1',
    });
  } catch (error) {
    // TODO: Add clean-up function that restores local file stores if an error is encountered while linking
    if (error.response) {
      return res.status(error.response.status).json({
        status: responseCodes.DEVICE_LINKING_EHUB_ERROR,
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

// Function for removing link of the device to a registered account in ehub-backend
async function unlinkDevice(req, res) {
  // No validation schema

  try {
    let token = await deviceService.checkAuthToken(); // Check auth token from file, don't proceed if this is not present

    const clearStreamsObject = await streamUtils.clearStreamsObject(); // stop all spawned child processes
    if (clearStreamsObject !== 'success') {
        throw new Error('Clearing streams object failed');
    }

    await deviceService.requestUnlinking(token); // send POST request to W1

    const deviceInfoJson = {
      deviceInfo: {
        network: null,
        station: null,
        location: null,
        channel: null,
        elevation: null,
        streamId: null,
      }
    };
    const deviceInfoPath = `${process.env.LOCALDBS_DIRECTORY}/deviceInfo.json`;
    await fs.writeFile(deviceInfoPath, JSON.stringify(deviceInfoJson)); // save empty device info values to json file

    const tokenJson = { accessToken: null, role: 'sensor' };
    const tokenPath = `${process.env.LOCALDBS_DIRECTORY}/token.json`;
    await fs.writeFile(tokenPath, JSON.stringify(tokenJson)); // save empty auth token value to json file

    const serversJson = [];
    const serversPath = `${process.env.LOCALDBS_DIRECTORY}/servers.json`;
    await fs.writeFile(serversPath, JSON.stringify(serversJson));

    return res.status(200).json({
      status: responseCodes.DEVICE_UNLINKING_SUCCESS,
      message: 'Successfully Requested Unlinking to W1',
    });
  } catch (error) {
    // TODO: Add clean-up function that restores local file stores if an error is encountered while unlinking
    if (error.response) {
      return res.status(error.response.status).json({
        status: responseCodes.DEVICE_UNLINKING_EHUB_ERROR,
        message: "Error from earthquake-hub: " + error.response.data.message,
      });
    } else {
      console.log(error)
      return res.status(500).json({
        status: responseCodes.DEVICE_UNLINKING_ERROR,
        message: error
      });
    }
  }
};


module.exports = { 
  getDeviceInfo, 
  linkDevice,
  unlinkDevice,
};