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
            .then(res => {
                // console.log(res)
                res.status(res.status).json({
                    status: 'success',
                    message: 'Succesfully Request Linking to W1'
                })
            })
            .catch(err => {
                // console.log(err.response)
                res.status(err.response.status).json({
                    status: 'error',
                    message: err.response.data.message
                })
            })
    })


module.exports = router;
