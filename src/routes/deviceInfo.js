const express = require('express');
const router = express.Router();
const fs = require('fs')
const bodyParser = require('body-parser')

router.use(bodyParser.json())

router.get('/', (req, res) => {
    fs.readFile('src/localDBs/deviceInfo.json', 'utf-8', function(err, jsonString){
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
            console.log(data.deviceInfo)
            res.json(data.deviceInfo)
        }
    })
})

router.post('/', (req, res) => {
    // TODO: Verify request body inputs and handle errors before writing to file.
    fs.writeFile("src/localDBs/deviceInfo.json", JSON.stringify(req.body), (err) => {
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