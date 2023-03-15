const express = require('express')
const cors = require('cors')
const app = express()
const bodyParser = require('body-parser')
const port = 5001 //Specify the port, if necessary
const fs = require('fs')
const getmac = require('getmac')

app.use(cors())

app.use(bodyParser.json())

app.get('/mac', (req, res) => {
    res.json(getmac.default())
})

app.get('/deviceInfo', (req, res) => {
    fs.readFile('./localDBs/deviceInfo.json', 'utf-8', function(err, jsonString){
        const data = JSON.parse(jsonString);
        console.log(data.deviceInfo)
        res.json(data.deviceInfo)
    })
})

app.get('/accountInfo', (req, res) => {
    fs.readFile('./localDBs/accountInfo.json', 'utf-8', function(err, jsonString){
        const data = JSON.parse(jsonString);
        console.log(data)
        res.json(data)
    })
})

app.get('/servers', (req, res) => {
    fs.readFile('./localDBs/servers.json', 'utf-8', function(err, jsonString){
        const data = JSON.parse(jsonString);
        console.log(data.servers)
        res.json(data.servers)
    })
})

app.post('/accountInfo', (req, res) => {
    fs.writeFile("./localDBs/accountInfo.json", JSON.stringify(req.body), (err) => {
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

app.post('/servers', (req, res) => {
    fs.writeFile("./localDBs/servers.json", JSON.stringify(req.body), (err) => {
        if (err)
            console.log(err);
        else {
            fs.readFile('./localDBs/servers.json', 'utf-8', function(err, jsonString){
                const data = JSON.parse(jsonString);
                console.log(data)
                res.json(data)
            })
        }
    });
})

app.post('/accountInfo', (req, res) => {
    fs.writeFile("./localDBs/accountInfo.json", JSON.stringify(req.body), (err) => {
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
  
app.listen(port, () => {
    console.log('App listening on port: ' + port)
})