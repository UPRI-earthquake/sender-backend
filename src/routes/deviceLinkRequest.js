const express = require('express');
const router = express.Router();
const fs = require('fs')
const getmac = require('getmac')
const axios = require('axios')
const { body, validationResult } = require('express-validator');
require('dotenv').config()

router.use(express.json())

// TODO: create a function for getting the device streamId
function generate_streamId() {
    const streamId = "AM_R3B2D_00_ENZ,AM_R3B2D_00_ENN" // mock values
    return streamId

    // TODO: Get streamID from rshake
    // TODO: Parse streamId and save details to deviceInfo.json
}

// Request token from auth server + save token to localDB 
// note: Always check if there's an existing token in localDB, if none, request from auth server
async function request_auth_token(username, password) {
    let retVal = null;
    try {
        const tokenString = await fs.promises.readFile('src/localDBs/token.json', 'utf-8');
        const data = JSON.parse(tokenString);
        console.log("accessToken read from json file: " + data.accessToken);
        if (data.accessToken != null) {
            retVal = data.accessToken;
        } else {
            console.log("ENV: " + process.env.NODE_ENV)
            let auth_url = (process.env.NODE_ENV === 'production')
                ? 'https://' + process.env.CLIENT_PROD_HOST + '/accounts/authenticate'
                : 'http://' + process.env.W1_DEV_HOST + ':' + process.env.W1_DEV_PORT + '/accounts/authenticate';
            console.log('auth_url: ' + auth_url)
            const credentials = {
                username: username,
                password: password,
                role: data.role
            };
            const response = await axios.post(auth_url, credentials);
            console.log("request_auth_token response: " + response.data.accessToken);
            console.dir(response)
            const jsonToken = {
                accessToken: response.data.accessToken,
                role: data.role
            };
            await fs.promises.writeFile("src/localDBs/token.json", JSON.stringify(jsonToken));
            retVal = response.data;
        }
    } catch (error) {
        console.log("request_auth_token error:" + error);
        retVal = error;
    }
    return retVal;
}

/* POST deviceLinkRequest endpoint */
router.post('/',
    body('username').not().isEmpty().trim().escape()
        .withMessage('Username Field Cannot be Empty'),
    body('password').not().isEmpty().trim().escape()
        .withMessage('Password Field Cannot be Empty'),
    body('notifyOnReply').toBoolean(),
    (req, res, next) => {
        // Finds the validation errors in this request and wraps them in an object with handy functions
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            res.status(400).json({ validationErrors: errors.array() }); //returns the error message in an array format
        } else {
            console.log('POST request received on /deviceLinkRequest endpoint')
            next()
        }
    }, async (req, res, next) => {
        try {
            const streamId = generate_streamId(); //get device streamId
            console.log("streamId Acquired: " + streamId) //logs the streamId acquired
            const macAddress = getmac.default(); //get device mac address
            console.log('Device Mac Address Acquired: ' + macAddress); //logs the Mac Address acquired

            const token = await request_auth_token(req.body.username, req.body.password);
            console.log("Returned value: " + token)
            if (!token) {
                res.status(400).json({ status: 400, message: 'Token Request/Validate Unsuccessful' })
                return
            }

            const json =
            {
                macAddress: macAddress,
                streamId: streamId
            };
            const url = (process.env.NODE_ENV === 'production')
                ? 'https://' + process.env.CLIENT_PROD_HOST + '/device/link'
                : 'http://' + process.env.W1_DEV_HOST + ':' + process.env.W1_DEV_PORT + '/device/link';

            const response = await axios.post(url, json, {
                headers: {
                    Authorization: `Bearer ${token}`
                }
            });

            res.status(response.status).json({
                status: response.status,
                message: 'Successfully Requested Linking to W1'
            });
        } catch (error) {
            console.log(error);

            if (error.response) {
                // The request was made and the server responded with a status code that falls out of the range of 2xx
                res.status(error.response.status).json({
                    status: error.response.status,
                    message: "Error from earthquake-hub: " + error.response.data.message
                });
            } else {
                // Something happened in setting up the request that triggered an Error
                res.status(500).json({
                    status: 500,
                    message: 'Internal Server Error'
                });
            }
        }

    })


module.exports = router;
