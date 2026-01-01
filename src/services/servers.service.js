const axios = require('axios');
const { buildW1BaseUrl } = require('./device.service');

async function requestRingserverHostsList() {
  try {
    const url = (process.env.NODE_ENV === 'production')
      ? 'https://' + process.env.W1_PROD_IP + '/accounts/ringserver-hosts'
      : 'http://' + process.env.W1_DEV_IP + ':' + process.env.W1_DEV_PORT + '/accounts/ringserver-hosts';

    const response = await axios.get(url);

    return response.data.payload; // Ringserver hosts list obtained from the response
  } catch (error) {
    console.log("requestRingserverHostsList() error:" + error);
    throw error; // Send the error to controller
  }
};

async function removeDeviceFromBrgyAccount(token, brgyUsername, streamId) {
  if (!token) {
    const err = new Error('Missing access token for device removal');
    err.code = 'MISSING_TOKEN';
    throw err;
  }
  if (!brgyUsername || !streamId) {
    const err = new Error('Missing brgyUsername or streamId for device removal');
    err.code = 'MISSING_PARAMS';
    throw err;
  }

  const url = `${buildW1BaseUrl()}/accounts/brgy/remove-device`;
  try {
    return await axios.post(
      url,
      { brgyUsername, streamId },
      { headers: { Authorization: `Bearer ${token}` } },
    );
  } catch (error) {
    console.log(`removeDeviceFromBrgyAccount() error: ${error}`);
    throw error;
  }
}

module.exports = {
  requestRingserverHostsList,
  removeDeviceFromBrgyAccount,
};
