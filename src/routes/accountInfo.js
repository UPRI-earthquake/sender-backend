const express = require('express');
const router = express.Router();
const fs = require('fs')
const bodyParser = require('body-parser')

router.use(bodyParser.json())

/* GET account information endpoint */
router.get('/', (req, res) => {
    fs.readFile('src/localDBs/accountInfo.json', 'utf-8', function(err, jsonString){
        if (err){
            console.log(err)
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
    fs.writeFile("src/localDBs/accountInfo.json", JSON.stringify(req.body), (err) => {
        if (err)
            console.log(err);
        else {
            fs.readFile('./localDBs/accountInfo.json', 'utf-8', function(err, jsonString){
                const data = JSON.parse(jsonString);
                console.log(data)
                res.json(data)
            })
        }
    });
})

module.exports = router;
