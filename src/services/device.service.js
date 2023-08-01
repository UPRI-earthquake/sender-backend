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

async function requestAuthToken(username, password) {
  try {
    let auth_url = (process.env.NODE_ENV === 'production')
      ? 'https://' + process.env.W1_PROD_IP + '/accounts/authenticate'
      : 'http://' + process.env.W1_DEV_IP + ':' + process.env.W1_DEV_PORT + '/accounts/authenticate';
    const credentials = {
      username: username,
      password: password,
      role: 'sensor'
    };

    const response = (process.env.NODE_ENV === 'production')
      ? await axios.post(auth_url, credentials, { httpsAgent })
      : await axios.post(auth_url, credentials)

    const filePath = `${process.env.LOCALDBS_DIRECTORY}/token.json`;
    const jsonToken = {
      accessToken: response.data.accessToken,
      role: 'sensor'
    };

    await fs.promises.writeFile(filePath, JSON.stringify(jsonToken));
    return response.data.accessToken;
  } catch (error) {
    console.log("requestAuthToken error:" + error);
    throw error; // Send the error to controller
  }
};


async function requestLinking(token) {
  try {
    const streamId = utils.generate_streamId();
    const macAddress = utils.read_mac_address();

    const json =
    {
      macAddress: macAddress,
      streamId: streamId
    };
    const url = (process.env.NODE_ENV === 'production')
      ? 'https://' + process.env.W1_PROD_IP + '/device/link'
      : 'http://' + process.env.W1_DEV_IP + ':' + process.env.W1_DEV_PORT + '/device/link';

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

    return response.data.payload; // The device information obtained from the response
  } catch (error) {
    console.log("requestLinking error:" + error);
    throw error; // Send the error to controller
  }
};

module.exports = {
  checkAuthToken,
  requestAuthToken,
  requestLinking,
};