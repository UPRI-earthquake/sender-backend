const express = require('express');
const router = express.Router();
const fs = require('fs')
const getmac = require('getmac')
const axios = require('axios')
const path = require('path');
const Joi = require('joi');
const https = require('https')
const httpsAgent = new https.Agent({ rejectUnauthorized: false });
const { generate_streamId } = require('./utils');

router.use(express.json())


/**
 * @swagger
 * /deviceLinkRequest:
 *   post:
 *     summary: Endpoint for linking the device to a registered account in earthquake-hub network (this endpoint is dependent to earthquake-hub-backend, meaning to test this endpoint make sure that ehub-backend container is up)
 *     tags:
 *       - Device
 *     requestBody:
 *       description: User credentials registered in earthquake-hub network
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               username:
 *                 type: string
 *                 description: Username registered in earthquake-hub network
 *               password:
 *                 type: string
 *                 description: Account's password
 *             example:
 *               username: citizen
 *               password: testpassword
 *     responses:
 *       200:
 *         description: Successful response with device information
 *       400:
 *         description: Device already linked to an existing account
 *       500:
 *         description: Internal server error
 */

// Request token from auth server + save token to localDB
// note: Always check if there's an existing token in localDB, if none, request from auth server
async function request_auth_token(username, password) {
    let retVal = null;

    try {
        const filePath = `${process.env.LOCALDBS_DIRECTORY}/token.json`
        let data = { accessToken: null, role: "sensor" };

        const tokenString = await fs.promises.readFile(filePath, 'utf-8');
        data = JSON.parse(tokenString);
        console.log("accessToken read from json file: " + data.accessToken);

        if (data.accessToken != null) {
            retVal = data.accessToken;
        } else {
            let auth_url = (process.env.NODE_ENV === 'production') 
                ? 'https://' + process.env.W1_PROD_IP + '/accounts/authenticate' 
                : 'http://' + process.env.W1_DEV_IP + ':' + process.env.W1_DEV_PORT + '/accounts/authenticate';
            console.log(auth_url)
            const credentials = {
                username: username,
                password: password,
                role: data.role
            };
		
            const response = (process.env.NODE_ENV === 'production')
                ? await axios.post(auth_url, credentials, { httpsAgent })
                : await axios.post(auth_url, credentials)
            console.log("request_auth_token response: " + response.data.accessToken);
            console.dir(response)
            const jsonToken = {
                accessToken: response.data.accessToken,
                role: data.role
            };
            await fs.promises.writeFile(filePath, JSON.stringify(jsonToken));
            retVal = response.data.accessToken;
        }
    } catch (error) {
        console.log("request_auth_token error:" + error);
        retVal = error;
    }
    return retVal;
}

const accountValidationSchema = Joi.object().keys({
  username: Joi.string().required(),
  password: Joi.string().pattern(new RegExp('^[a-zA-Z0-9]{6,30}$')).required()
});

/* POST deviceLinkRequest endpoint */
router.post('/', async (req, res, next) => {
        try {
            // Validate input
            const result = accountValidationSchema.validate(req.body);
            if(result.error){
                console.log(result.error.details[0].message)
                return res.status(400).json({ status: 400, message: result.error.details[0].message });
            }

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
                ? 'https://' + process.env.W1_PROD_IP + '/device/link'
                : 'http://' + process.env.W1_DEV_IP + ':' + process.env.W1_DEV_PORT + '/device/link';

            const response = (process.env.NODE_ENV === 'production')
             ? await axios.post(url, json, {
                    httpsAgent,
                    headers: {
                        Authorization: `Bearer ${token}`
                    }
                })
            : await axios.post(url,json, {
                    headers: {
                        Authorization: `Bearer ${token}`
                    }
                })
            
            const deviceInfoPath = `${process.env.LOCALDBS_DIRECTORY}/deviceInfo.json`
            // Save deviceInfo coming from the response from request to W1
            await fs.promises.writeFile(deviceInfoPath, JSON.stringify(response.data.payload));

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
