const axios = require('axios');

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

module.exports = {
  requestRingserverHostsList,
};