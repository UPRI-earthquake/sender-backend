const express = require('express');
const router = express.Router();
const fs = require('fs')
const bodyParser = require('body-parser')
const getmac = require('getmac')

router.use(bodyParser.json())

/* GET account information endpoint */
router.get('/', (req, res) => {
    fs.readFile('src/localDBs/accountInfo.json', 'utf-8', function(err, jsonString){
        if (err) {
            console.log(err);
            res.status(500).json(
                {
                    status: 'Error reading json',
                    message: err
                }
            );
        }
        else {
            const data = JSON.parse(jsonString);
            console.log(data)
            res.json(data)
        }
    })
})

/* POST account information endpoint */
router.post('/', (req, res) => {
    const macAddress = getmac.default(); //get device mac address
    const reqInfo = req.body; //get input

    // TODO: Handle empty or undesired request body errors before saving to the file.

    const json = 
        {
            accountName: reqInfo.accountName,
            accountPassword: reqInfo.accountPassword,
            macAddress: macAddress 
        };

    fs.writeFile("src/localDBs/accountInfo.json", JSON.stringify(json), (err) => {
        if (err) {
            console.log(err);
            res.status(500).json(
                {
                    status: 'Error reading json',
                    message: err
                }
            );
        }
        else {
            fs.readFile('src/localDBs/accountInfo.json', 'utf-8', function(err, jsonString){
                if (err) {
                    console.log(err);
                    res.status(500).json(
                        {
                            status: 'Error reading json',
                            message: err
                        }
                    );
                }
                else {
                    const data = JSON.parse(jsonString);
                    console.log(data);
                    res.json(data);
                }
            })
        }
    });
})

module.exports = router;
