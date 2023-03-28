const express = require('express');
const router = express.Router();
const fs = require('fs')
const getmac = require('getmac')
const request = require('request')
const { body, validationResult } = require('express-validator');
require('dotenv').config()

router.use(express.json())


/* POST deviceLinkRequest endpoint */
router.post('/',
    body('accountName').not().isEmpty().trim().escape()
        .withMessage('Username Cannot be Empty'),
    body('accountPassword').not().isEmpty().trim().escape()
        .withMessage('Password Cannot be Empty'),
    body('notifyOnReply').toBoolean(),
    (req, res, next) => {
        // Finds the validation errors in this request and wraps them in an object with handy functions
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            res.status(400).json({ validationErrors: errors.array() }); //returns the error message in an array format
            // next({err: errors.array()})
        } else{
            console.log('POST request received on /deviceLinkRequest endpoint')
            next()
        }
    }, (req, res, next) => {
        const macAddress = getmac.default(); //get device mac address
        console.log('Device Mac Address Acquired: ' + macAddress); //logs the Mac Address acquired

        const url = (process.env.NODE_ENV === 'production')
            ? 'https://' + process.env.CLIENT_PROD_HOST + '/deviceLinkHandler'
            : 'http://' + process.env.CLIENT_DEV_HOST + ':' + process.env.CLIENT_DEV_PORT + '/deviceLinkHandler';

        const json =
        {
            accountName: req.body.accountName,
            accountPassword: req.body.accountPassword,
            macAddress: macAddress
        };

        // POST request to W1
        request.post(url, json, (error, response, body) => {
            // TODO: Process response from W1-handler before sending success or error message
            if (!error && response.statusCode == 200) { 
                console.log('POST request body: ' + body);
                res.status(200).json({
                    error: 0,
                    status: 'success',
                    message: 'Succesfully Request Linking to W1'
                })
            } else {
                res.status(500).json({
                    error: 2,
                    status: 'error',
                    message: 'Cannot reach W1 Device Link Handler endpoint'
                })
            }
        })
    })


module.exports = router;
