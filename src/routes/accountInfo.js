const express = require('express');
const router = express.Router();
const fs = require('fs')
require('dotenv').config()

/* GET account information endpoint */
router.get('/', (req, res) => {
    // throw new Error('This is my created error')
    fs.readFile('src/localDBs/accountInfo.json', 'utf-8', (err, jsonString) => {
        const data = JSON.parse(jsonString);
        console.log(data)
        res.json(data)
    })
})

module.exports = router;
