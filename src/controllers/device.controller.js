const deviceService = require('../services/device.service');
const streamUtils = require('./stream.utils');
const Joi = require('joi');
const { responseCodes, responseMessages } = require('./responseCodes');

// Function for getting the information of the device saved in local file store
async function getDeviceInfo(req, res) {
  try {
    const { deviceInfo, hostConfig, linked, tokenStatus, refreshTokenStatus } = await deviceService.getDeviceDetails();

    res.status(200).json({ 
      status: responseCodes.GET_DEVICE_INFO_SUCCESS,
      message: 'Get device information success', 
      payload: {
        ...deviceInfo,
        linked,
        hostConfig,
        tokenStatus,
        refreshTokenStatus,
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
      .required(),
    forceRelink: Joi.boolean().optional(),
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
    const {
      accessToken,
      refreshToken = null,
      deviceInfo,
    } = payload || {};

    if (!accessToken) {
      throw new Error('Link response missing access token from W1');
    }

    await deviceService.persistTokenPair({
      accessToken,
      refreshToken,
      deviceInfo,
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
        message: error?.message || 'Device linking failed',
      });
    }
  }
};

// Function for removing link of the device to a registered account in ehub-backend
async function unlinkDevice(req, res) {
  const localOnly = req.query.localOnly === 'true' || req.body?.localOnly === true;

  try {
    const unlinkIdentifiers = !localOnly ? await deviceService.getUnlinkIdentifiers() : null;

    // Stop all spawned child processes before attempting unlink
    const clearedStreams = await streamUtils.clearStreamsObject();
    if (clearedStreams !== 'success') {
      throw new Error('Clearing streams object failed');
    }

    if (!localOnly) {
      if (!unlinkIdentifiers?.streamId || !unlinkIdentifiers?.macAddress) {
        return res.status(400).json({
          status: responseCodes.DEVICE_UNLINKING_ERROR,
          message: 'Missing device identifiers needed to unlink remotely.',
        });
      }

      const token = await deviceService.ensureValidAccessToken(); // Check/refresh auth token from file
      await deviceService.requestUnlinking(token, unlinkIdentifiers); // send POST request to W1
    }

    await deviceService.clearLocalLinkState();

    return res.status(200).json({
      status: responseCodes.DEVICE_UNLINKING_SUCCESS,
      message: localOnly
        ? 'Local link state cleared'
        : 'Successfully unlinked device from Earthquake Hub and cleared local state',
    });
  } catch (error) {
    console.log(error);

    if (localOnly) {
      try {
        await deviceService.clearLocalLinkState();
      } catch (cleanupError) {
        console.log(cleanupError);
      }
    }

    if (error.response) {
      return res.status(error.response.status).json({
        status: responseCodes.DEVICE_UNLINKING_EHUB_ERROR,
        message: "Error from earthquake-hub: " + error.response.data.message,
      });
    } else if (error.code === 'MISSING_UNLINK_IDENTIFIERS') {
      return res.status(400).json({
        status: responseCodes.DEVICE_UNLINKING_ERROR,
        message: 'Missing device identifiers needed to unlink remotely.',
      });
    } else {
      return res.status(500).json({
        status: responseCodes.DEVICE_UNLINKING_ERROR,
        message: localOnly
          ? 'Unable to clear local link state'
          : 'Unlink failed before clearing local state. Check token status or use Reset Link State.',
      });
    }
  }
};

// Manual token refresh (bypass scheduler)
async function refreshAccessToken(req, res) {
  try {
    await deviceService.refreshAuthToken();
    const [tokenStatus, refreshTokenStatus] = await Promise.all([
      deviceService.getAccessTokenStatus(),
      deviceService.getRefreshTokenStatus(),
    ]);

    return res.status(200).json({
      status: responseCodes.DEVICE_TOKEN_REFRESH_SUCCESS,
      message: 'Access token refreshed',
      payload: {
        tokenStatus,
        refreshTokenStatus,
      },
    });
  } catch (error) {
    console.log(error);
    return res.status(500).json({
      status: responseCodes.DEVICE_TOKEN_REFRESH_ERROR,
      message: error?.message || 'Unable to refresh access token',
    });
  }
}


module.exports = { 
  getDeviceInfo, 
  linkDevice,
  unlinkDevice,
  refreshAccessToken,
};
