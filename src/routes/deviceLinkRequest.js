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
            : 'http://' + process.env.W1_DEV_HOST + ':' + process.env.W1_DEV_PORT + '/deviceLinkHandler';

        const json =
        {
            accountName: req.body.accountName,
            accountPassword: req.body.accountPassword,
            macAddress: macAddress
        };

        console.log(url)

        axios.post(url, json)
            .then(response => {
                // console.log(response)
                res.status(response.status).json({
                    status: 'success',
                    message: 'Succesfully Request Linking to W1'
                })
            })
            .catch(error => {
                // console.log(error)
                if (error.response) {
                    // The request was made and the server responded with a status code that falls out of the range of 2xx
                    res.status(error.response.status).json({
                        status: 'error',
                        message: error.response.data.message
                    })
                } else {
                    // Something happened in setting up the request that triggered an Error
                    next(error) // Send error to express default error handler
                }
            })
    })


module.exports = router;
