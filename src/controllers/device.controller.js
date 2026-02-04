const deviceService = require('../services/device.service');
const streamUtils = require('./stream.utils');
const Joi = require('joi');
const { responseCodes, responseMessages } = require('./responseCodes');
const serversService = require('../services/servers.service');

// Function for getting the information of the device saved in local file store
async function getDeviceInfo(req, res) {
  try {
    const {
      deviceInfo,
      hostConfig,
      linked,
      tokenStatus,
      refreshTokenStatus,
      linkState,
    } = await deviceService.getDeviceDetails();

    res.status(200).json({ 
      status: responseCodes.GET_DEVICE_INFO_SUCCESS,
      message: 'Get device information success', 
      payload: {
        ...deviceInfo,
        linked,
        hostConfig,
        tokenStatus,
        refreshTokenStatus,
        linkState,
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
	    password: Joi.string().min(1).max(256).required(),
	    longitude: Joi.string()
	      .regex(/^[-+]?(?:180(?:\.0{1,6})?|(?:1[0-7]\d|0?\d{1,2})(?:\.\d{1,6})?)$/)
	      .required(),
	    latitude: Joi.string()
	      .regex(/^[-+]?(?:90(?:\.0{1,6})?|(?:[0-8]?\d(?:\.\d{1,6})?))$/)
	      .required(),
	    elevation: Joi.string()
	      .regex(/^[-+]?\d+(\.\d+)?$/)
	      .required(),
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
	      const statusCode = error.response.status;
	      const backendMessageRaw = error.response?.data?.message;
	      const backendMessage = typeof backendMessageRaw === 'string'
	        ? backendMessageRaw.trim()
	        : backendMessageRaw
	          ? String(backendMessageRaw)
	          : '';
	
	      let message = backendMessage
	        ? `Error from earthquake-hub: ${backendMessage}`
	        : `Error from earthquake-hub (status ${statusCode})`;
	
	      if (statusCode === 409) {
	        if (backendMessage && /already\s+linked/i.test(backendMessage)) {
	          message = 'Device already linked in Earthquake Hub. Use Reset Link or contact support to move it.';
	        } else if (backendMessage) {
	          message = backendMessage; // Avoid assuming the nature of the conflict
	        } else {
	          message = 'Conflict response from earthquake-hub while linking device.';
	        }
	      }
	
	      return res.status(error.response.status).json({
	        status: responseCodes.DEVICE_LINKING_EHUB_ERROR,
	        message,
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
      try {
        await serversService.removeDeviceFromAllBrgyAccounts(token, unlinkIdentifiers.streamId);
      } catch (cleanupError) {
        console.log(`Brgy cleanup error during unlink: ${cleanupError}`);
        // Proceed without failing the unlink; cleanup was best-effort
      }
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
    } else if (error.code === 'RELINK_REQUIRED') {
      return res.status(409).json({
        status: responseCodes.DEVICE_RELINK_REQUIRED,
        message: error.message || 'Device credentials expired. Use Reset Link State to relink this device.',
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

async function resetLinkState(req, res) {
  let localCleared = false;
  let unlinkIdentifiers = null;
  let streamsCleared = false;
  let remoteResetOutcome = { attempted: false, success: false };

  try {
    unlinkIdentifiers = await deviceService.getUnlinkIdentifiers();

    if (!unlinkIdentifiers?.streamId || !unlinkIdentifiers?.macAddress) {
      return res.status(400).json({
        status: responseCodes.DEVICE_RESET_ERROR,
        message: 'Missing device identifiers needed to reset link state.',
      });
    }

    const clearedStreams = await streamUtils.clearStreamsObject();
    if (clearedStreams !== 'success') {
      throw new Error('Clearing streams object failed');
    }
    streamsCleared = true;

    let token = null;
    try {
      token = await deviceService.ensureValidAccessToken();
    } catch (tokenErr) {
      console.log('Valid access token unavailable for reset, continuing without bearer token:', tokenErr.message);
    }

    await deviceService.clearLocalLinkState();
    localCleared = true;

    try {
      remoteResetOutcome.attempted = true;
      await deviceService.requestLinkReset(token, unlinkIdentifiers);
      remoteResetOutcome.success = true;
    } catch (remoteErr) {
      remoteResetOutcome.error = remoteErr;

      // If we already cleared local state, treat "auth required" or "not found" as non-fatal:
      // - auth required: common when upgrading from older deployments with invalid/missing tokens
      // - not found: device record already removed remotely
      const status = remoteErr?.response?.status;
      const remoteMessage = remoteErr?.response?.data?.message;
      if (localCleared && (status === 401 || status === 404)) {
        return res.status(200).json({
          status: responseCodes.DEVICE_RESET_SUCCESS,
          message: status === 401
            ? 'Local link state cleared. Remote reset requires signing in as the linked account. Use Link Device to link this device again.'
            : 'Local link state cleared. Device record not found on Earthquake Hub. Use Link Device to link this device again.',
          payload: {
            remoteReset: false,
            remoteStatus: status,
            remoteMessage: remoteMessage || null,
          },
        });
      }

      throw remoteErr;
    }

    return res.status(200).json({
      status: responseCodes.DEVICE_RESET_SUCCESS,
      message: 'Device link reset. Use Link Device to link this device again.',
      payload: {
        remoteReset: true,
      },
    });
  } catch (error) {
    console.log(error);

    if (!streamsCleared) {
      try {
        await streamUtils.clearStreamsObject();
      } catch (cleanupError) {
        console.log(cleanupError);
      }
    }

    if (!localCleared) {
      try {
        await deviceService.clearLocalLinkState();
      } catch (cleanupError) {
        console.log(cleanupError);
      }
    }

    if (error.response) {
      return res.status(error.response.status).json({
        status: responseCodes.DEVICE_RESET_EHUB_ERROR,
        message: error.response?.data?.message
          || 'Error from earthquake-hub while resetting link state',
        payload: remoteResetOutcome.attempted
          ? {
            remoteReset: false,
            remoteStatus: error.response.status,
          }
          : undefined,
      });
    }

    if (error.code === 'MISSING_RESET_IDENTIFIERS') {
      return res.status(400).json({
        status: responseCodes.DEVICE_RESET_ERROR,
        message: 'Missing device identifiers needed to reset link state.',
      });
    }

    if (error.code === 'RELINK_REQUIRED') {
      return res.status(409).json({
        status: responseCodes.DEVICE_RELINK_REQUIRED,
        message: error.message || 'Device credentials expired. Relink before resetting link state.',
      });
    }

    if (error.message === 'Clearing streams object failed') {
      return res.status(500).json({
        status: responseCodes.DEVICE_RESET_ERROR,
        message: 'Unable to stop existing streams before resetting link.',
      });
    }

    return res.status(500).json({
      status: responseCodes.DEVICE_RESET_ERROR,
      message: 'Reset failed before completing cleanup.',
    });
  }
}

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
    if (error?.code === 'RELINK_REQUIRED') {
      const refreshTokenStatus = await deviceService.getRefreshTokenStatus();
      return res.status(409).json({
        status: responseCodes.DEVICE_RELINK_REQUIRED,
        message: error.message || 'Refresh token unavailable. Relink the device to continue streaming.',
        payload: {
          refreshTokenStatus,
        },
      });
    }
    return res.status(500).json({
      status: responseCodes.DEVICE_TOKEN_REFRESH_ERROR,
      message: error?.message || 'Unable to refresh access token',
    });
  }
}

async function refreshHostMetadata(req, res) {
  try {
    const refreshed = await deviceService.refreshDeviceMetadataFromHost();
    return res.status(200).json({
      status: responseCodes.DEVICE_HOST_CONFIG_REFRESH_SUCCESS,
      message: responseMessages.DEVICE_HOST_CONFIG_REFRESH_SUCCESS,
      payload: refreshed,
    });
  } catch (error) {
    console.error('Error refreshing host metadata', error);

    const statusCode = responseCodes.DEVICE_HOST_CONFIG_REFRESH_ERROR;
    const clientErrors = ['HOST_CONFIG_UNAVAILABLE', 'HOST_CONFIG_EMPTY'];

    if (clientErrors.includes(error.code)) {
      return res.status(400).json({
        status: statusCode,
        message: error.message,
      });
    }

    return res.status(500).json({
      status: statusCode,
      message: error?.message || responseMessages.DEVICE_HOST_CONFIG_REFRESH_ERROR,
    });
  }
}


module.exports = { 
  getDeviceInfo, 
  linkDevice,
  unlinkDevice,
  resetLinkState,
  refreshAccessToken,
  refreshHostMetadata,
};
