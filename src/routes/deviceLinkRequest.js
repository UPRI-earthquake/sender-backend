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
    const streamId = "AM_R3B2D_00_ENZ, AM_R3B2D_00_ENN" // mock values
    return streamId

    // TODO: Get streamID from rshake
    // TODO: Parse streamId and save details to deviceInfo.json
}

// TODO: Request token from auth server + save token to localDB 
// note: Always check if there's an existing token in localDB, if none, request from auth server
function request_auth_token(username, password) {
    // TODO: check if token.json is not null. If null, request a token. Else, verify token from auth server.
    fs.readFile('src/localDBs/token.json', 'utf-8', function (err, tokenString) {
        const data = JSON.parse(tokenString);
        console.log("accessToken read from json file: " + data.accessToken)
        
        let endpoint = null
        if (data.accessToken != null) { // token exists, needs verification
            endpoint = "/verifySensorToken";
        } else { // token is null, request 
            endpoint = "/authenticate";
        }

        const auth_url = (process.env.NODE_ENV === 'production')
            ? 'https://' + process.env.CLIENT_PROD_HOST + '/accounts' + endpoint
            : 'http://' + process.env.W1_DEV_HOST + ':' + process.env.W1_DEV_PORT + '/accounts' + endpoint
        console.log(auth_url)
        const credentials = 
        {
            username: username,
            password: password,
            role: data.role,
            token: data.accessToken
        }

        // Send the username and password inputs to auth server
        axios.post(auth_url, credentials)
            .then(response => {
                console.log("request_auth_token response: " +response)
                return response
            })
            .catch(error => {
                console.log("request_auth_token error:" +error)
            })
    })
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
        } else{
            console.log('POST request received on /deviceLinkRequest endpoint')
            next()
        }
    }, (req, res, next) => {
        const streamId = generate_streamId(); //get device streamId
        console.log("streamId Acquired: " + streamId) //logs the streamId acquired
        const macAddress = getmac.default(); //get device mac address
        console.log('Device Mac Address Acquired: ' + macAddress); //logs the Mac Address acquired

        const token = request_auth_token(req.body.username, req.body.password);
        const accessToken = token.accessToken
        const jsonToken = { accessToken: accessToken }
        // Save token to a json file in localDB
        fs.writeFile("src/localDBs/token.json", JSON.stringify(jsonToken), (err, next) => {
            // if (err){
            //     next(err)
            // }
        });

        const json =
        {
            token: accessToken,
            macAddress: macAddress,
            streamId: streamId
        };
        const url = (process.env.NODE_ENV === 'production')
            ? 'https://' + process.env.CLIENT_PROD_HOST + '/device/link'
            : 'http://' + process.env.W1_DEV_HOST + ':' + process.env.W1_DEV_PORT + '/device/link';

        axios.post(url, json)
            .then(response => {
                // console.log(response)
                res.status(response.status).json({
                    status: response.status,
                    message: 'Succesfully Request Linking to W1'
                })
            })
            .catch(error => {
                // console.log(error)
                if (error.response) {
                    // The request was made and the server responded with a status code that falls out of the range of 2xx
                    res.status(error.response.status).json({
                        status: error.response.status,
                        message: error.response.data.message
                    })
                } else {
                    // Something happened in setting up the request that triggered an Error
                    res.status(500).json({
                        status: 500,
                        message: "Internal Server Error"//error.response.data.message
                    })
                }
            })
    })


module.exports = router;
