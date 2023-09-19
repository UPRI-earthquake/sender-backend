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

    let data = defaultDeviceInfo;

    const jsonString = await fs.readFile(filePath, 'utf-8');
    data = JSON.parse(jsonString);

    // console.log(data.deviceInfo);
    res.status(200).json({ 
      status: responseCodes.GET_DEVICE_INFO_SUCCESS,
      message: 'Get device information success', 
      payload: data});
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
    longitude: Joi.string()
      .regex(/^[-+]?(?:180(?:\.0{1,6})?|(?:1[0-7]\d|0?\d{1,2})(?:\.\d{1,6})?)$/)
      .required(),
    latitude: Joi.string()
      .regex(/^[-+]?(?:90(?:\.0{1,6})?|(?:[0-8]?\d(?:\.\d{1,6})?))$/)
      .required(),
    elevation: Joi.string()
      .regex(/^[-+]?\d+(\.\d+)?$/)
      .required()
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
      else if (errorMessage.includes('longitude')) {
        statusCode = responseCodes.DEVICE_LINKING_INVALID_LONGITUDE_VALUE
      } 
      else if (errorMessage.includes('latitude')) {
        statusCode = responseCodes.DEVICE_LINKING_INVALID_LATITUDE_VALUE
      } 
      else if (errorMessage.includes('elevation')) {
        statusCode = responseCodes.DEVICE_LINKING_INVALID_ELEVATION_VALUE
      } 

      return res.status(401).json({ 
        status: statusCode, 
        message: `Input error: ${errorMessage}` });
    }

    // Link the device and save device information to json file
    const payload = await deviceService.requestLinking(req.body);

    // Save returned token, from W1, to json file
    const tokenInfo = { accessToken: payload.accessToken }
    const tokenPath = `${process.env.LOCALDBS_DIRECTORY}/token.json`;
    await fs.writeFile(tokenPath, JSON.stringify(tokenInfo));

    // Save device information to json file
    const deviceInfoPath = `${process.env.LOCALDBS_DIRECTORY}/deviceInfo.json`;
    await fs.writeFile(deviceInfoPath, JSON.stringify(payload.deviceInfo));

    return res.status(200).json({
      status: responseCodes.DEVICE_LINKING_SUCCESS,
      message: 'Successfully Requested Linking to W1',
    });
  } catch (error) {
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