const deviceService = require('../services/device.service');
const streamUtils = require('./stream.utils');
const Joi = require('joi');
const { responseCodes, responseMessages } = require('./responseCodes');

// Function for getting the information of the device saved in local file store
async function getDeviceInfo(req, res) {
  try {
    const { deviceInfo, hostConfig, linked } = await deviceService.getDeviceDetails();

    res.status(200).json({ 
      status: responseCodes.GET_DEVICE_INFO_SUCCESS,
      message: 'Get device information success', 
      payload: {
        ...deviceInfo,
        linked,
        hostConfig,
      }});
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

    await deviceService.persistToken(payload.accessToken);
    await deviceService.persistDeviceInfo(payload.deviceInfo);
    await deviceService.persistCredentials({
      username: req.body.username,
      password: req.body.password,
      longitude: req.body.longitude,
      latitude: req.body.latitude,
      elevation: req.body.elevation,
      forceRelink: true,
    });

    return res.status(200).json({
      status: responseCodes.DEVICE_LINKING_SUCCESS,
      message: 'Successfully Requested Linking to W1',
    });
  } catch (error) {
    if (error.response) {
      return res.status(error.response.status).json({
        status: responseCodes.DEVICE_LINKING_EHUB_ERROR,
        message: error.response?.status === 409
          ? "Device already linked in Earthquake Hub. Use Reset Link or contact support to move it."
          : "Error from earthquake-hub: " + error.response.data.message,
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
  const localOnly = req.query.localOnly === 'true' || req.body?.localOnly === true;

  try {
    let remoteUnlinkAttempted = false;
    if (!localOnly) {
      const token = await deviceService.ensureValidAccessToken(); // Check/refresh auth token from file

      const clearStreamsObject = await streamUtils.clearStreamsObject(); // stop all spawned child processes
      if (clearStreamsObject !== 'success') {
          throw new Error('Clearing streams object failed');
      }

      await deviceService.requestUnlinking(token); // send POST request to W1
      remoteUnlinkAttempted = true;
    } else {
      await streamUtils.clearStreamsObject();
    }

    await deviceService.clearLocalLinkState();

    return res.status(200).json({
      status: responseCodes.DEVICE_UNLINKING_SUCCESS,
      message: remoteUnlinkAttempted
        ? 'Successfully Requested Unlinking to W1'
        : 'Local link state cleared',
    });
  } catch (error) {
    if (!localOnly) {
      // Try to clear local state and stop streams even if remote unlink fails
      await streamUtils.clearStreamsObject();
      await deviceService.clearLocalLinkState();
    }

    if (error.response) {
      return res.status(error.response.status).json({
        status: responseCodes.DEVICE_UNLINKING_EHUB_ERROR,
        message: "Error from earthquake-hub: " + error.response.data.message,
      });
    } else {
      console.log(error);
      return res.status(200).json({
        status: responseCodes.DEVICE_UNLINKING_SUCCESS,
        message: 'Local link state cleared. Remote unlink may have failed; re-link to refresh token.',
      });
    }
  }
};

// Function for clearing link state without contacting W1 (for re-installs/relinking)
async function resetLinkState(req, res) {
  req.query.localOnly = 'true';
  return unlinkDevice(req, res);
}


module.exports = { 
  getDeviceInfo, 
  linkDevice,
  unlinkDevice,
  resetLinkState,
};
