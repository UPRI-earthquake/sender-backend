const express = require('express');
const router = express.Router();
const fs = require('fs')
const getmac = require('getmac')
const axios = require('axios')
const { body, validationResult } = require('express-validator');
require('dotenv').config()

router.use(express.json())


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
        // Read the device info saved on json file
        fs.readFile('src/localDBs/deviceInfo.json', 'utf-8', function (err, jsonString) {
            const data = JSON.parse(jsonString);
            console.log('Device info read from json file: ' + data.deviceInfo)
            const deviceInfo = data.deviceInfo

            // TO-DO: validate device info from json file. Network, location, station should not be null to proceed.
            if (deviceInfo.network == null || deviceInfo.location == null || deviceInfo.station == null) {
                res.status(400).json({ status: 400, message: "Device Information not yet set. Update device information first before linking." })
            } else{
                const macAddress = getmac.default(); //get device mac address
                console.log('Device Mac Address Acquired: ' + macAddress); //logs the Mac Address acquired

                const url = (process.env.NODE_ENV === 'production')
                    ? 'https://' + process.env.CLIENT_PROD_HOST + '/device/link'
                    : 'http://' + process.env.W1_DEV_HOST + ':' + process.env.W1_DEV_PORT + '/device/link';

                const json =
                {
                    username: req.body.username,
                    password: req.body.password,
                    network: deviceInfo.network,
                    station: deviceInfo.station,
                    location: deviceInfo.location,
                    macAddress: macAddress
                };

                console.log(url)

                axios.post(url, json)
                    .then(response => {
                        console.log(response)
                        res.status(response.status).json({
                            status: response.status,
                            message: 'Succesfully Request Linking to W1'
                        })
                    })
                    .catch(error => {
                        console.log(error)
                        if (error.response) {
                            // The request was made and the server responded with a status code that falls out of the range of 2xx
                            res.status(error.response.status).json({
                                status: error.response.status,
                                message: error.response.data.message
                            })
                        } else {
                            // Something happened in setting up the request that triggered an Error
                            next(error) // Send error to express default error handler
                        }
                    })
            }
        })
        
    })


module.exports = router;
