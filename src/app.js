const express = require('express')
const cors = require('cors')
const bodyParser = require('body-parser')
const fs = require('fs')
const path = require('path');   
require('dotenv').config()

const app = express()
const port = process.env.NODE_ENV === 'production'
             ? process.env.BACKEND_PROD_PORT
             : process.env.BACKEND_DEV_PORT;

const deviceInfoRouter = require('./routes/deviceInfo')
const serversRouter = require('./routes/servers')
const deviceLinkRequestRouter = require('./routes/deviceLinkRequest')

app.use(cors())
// Allow all request from all sources for now. TODO: restrict cross-origin requests
// app.use(cors({origin : process.env.NODE_ENV === 'production'
//   ? 'http://' + process.env.CLIENT_PROD_HOST
//   : 'http://' + process.env.CLIENT_DEV_HOST
// }))

app.use(bodyParser.json())

app.use('/deviceInfo', deviceInfoRouter)
app.use('/servers', serversRouter)
app.use('/deviceLinkRequest', deviceLinkRequestRouter)

// Function for creating local file store directory and files if it doesn't exists
async function createLocalFileStoreDir() {
    try {
        // Create /localDBs/ directory
        const localFileStoreDir = path.join(__dirname, '/localDBs')
        try {
            await fs.promises.access(localFileStoreDir, fs.constants.R_OK);
            console.log(`./localDBs/ folder already exists`);
        } catch (error) {
            await fs.promises.mkdir(localFileStoreDir);
            console.log(`./localDBs/ folder created`);
        }

        // Create token.json if it doesn't exists
        try {
            await fs.promises.access(`${localFileStoreDir}/token.json`, fs.constants.R_OK);
            console.log(`token.json already exists.`);
        } catch (error) {
            const tokenJson = { accessToken: null, role: 'sensor' };
            await fs.promises.writeFile(`${localFileStoreDir}/token.json`, JSON.stringify(tokenJson));
            console.log(`token.json created.`);
        }
        

        // Create servers.json if it doesn't exists
        try {
            await fs.promises.access(`${localFileStoreDir}/servers.json`, fs.constants.R_OK);
            console.log(`servers.json already exists.`);
          } catch (error) {
            const serversJson = [];
            await fs.promises.writeFile(`${localFileStoreDir}/servers.json`, JSON.stringify(serversJson));
            console.log(`servers.json created.`);
          }

        // Create deviceInfo.json if it doesn't exists
        try {
            await fs.promises.access(`${localFileStoreDir}/deviceInfo.json`, fs.constants.R_OK);
            console.log(`deviceInfo.json already exists.`);
        } catch (error) {
            const deviceInfoJson = {
                deviceInfo: {
                    network: null,
                    station: null,
                    location: null,
                    channel: null,
                    elevation: null,
                    streamId: null,
                },
            };
            await fs.promises.writeFile(`${localFileStoreDir}/deviceInfo.json`, JSON.stringify(deviceInfoJson));
            console.log(`deviceInfo.json created.`);
        }
    } catch (error) {
        console.log(`${error}`)
    }
}

createLocalFileStoreDir();

/* Error handler middleware */
app.use((err, req, res, next) => {
    const statusCode = err.statusCode || 500;
    //console.trace(`Express error handler captured the following...\n ${err}`);
    (process.env.NODE_ENV === 'production') // Provide different error response on prod and dev
    ? res.status(statusCode).json({"message": "Server error occured"}) // TODO: make a standard api message for error
    : res.status(statusCode).json({
        'status': "Express error handler caught an error",
        'err': err.stack,
        'note': 'This error will only appear on non-production env'});
    return;
});

module.exports = app;