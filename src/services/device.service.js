const fs = require('fs');
const axios = require('axios');
const https = require('https');
const httpsAgent = new https.Agent({ rejectUnauthorized: false });
const utils = require('./utils');


// Function for checking if a jwt access token is already saved 
async function checkAuthToken() {
  // TODO: check validity of jwt
  try {
    const filePath = `${process.env.LOCALDBS_DIRECTORY}/token.json`;
    let data = { accessToken: null, role: "sensor" };

    const tokenString = await fs.promises.readFile(filePath, 'utf-8');
    data = JSON.parse(tokenString);

    return data.accessToken;
  } catch (error) {
    console.log("Error:" + error);
    throw 'Error reading file';
  }
}


// Function for adding the device to db in W1 and linking it to the user input account details
async function requestLinking(userInput) {
  try {
    const streamId = utils.generate_streamId();
    const macAddress = utils.read_mac_address();

    const json =
    {
      username: userInput.username,
      password: userInput.password,
      role: 'sensor',
      longitude: userInput.longitude,
      latitude: userInput.latitude,
      elevation: userInput.elevation,
      macAddress: macAddress,
      streamId: streamId
    };
    const url = (process.env.NODE_ENV === 'production')
      ? 'https://' + process.env.W1_PROD_IP + '/device/link'
      : 'http://' + process.env.W1_DEV_IP + ':' + process.env.W1_DEV_PORT + '/device/link';

    const response = await axios.post(url, json)

    return response.data.payload; // The device information obtained from the response
  } catch (error) {
    console.log("requestLinking error:" + error);
    throw error; // Send the error to controller
  }
};


async function requestUnlinking(token) {
  try {
    const streamId = utils.generate_streamId();
    const macAddress = utils.read_mac_address();

    const json =
    {
      macAddress: macAddress,
      streamId: streamId
    };
    const url = (process.env.NODE_ENV === 'production')
      ? 'https://' + process.env.W1_PROD_IP + '/device/unlink'
      : 'http://' + process.env.W1_DEV_IP + ':' + process.env.W1_DEV_PORT + '/device/unlink';

    const response = (process.env.NODE_ENV === 'production')
      ? await axios.post(url, json, {
        httpsAgent,
        headers: {
          Authorization: `Bearer ${token}`
        }
      })
      : await axios.post(url, json, {
        headers: {
          Authorization: `Bearer ${token}`
        }
      })

    return 'success'; // Device unlinking successful
  } catch (error) {
    console.log("Unlinking request error:" + error);
    throw error; // Send the error to controller
  }
};

module.exports = {
  checkAuthToken,
  requestLinking,
  requestUnlinking,
};