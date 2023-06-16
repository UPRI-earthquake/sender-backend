const express = require('express')
const cors = require('cors')
const bodyParser = require('body-parser')

const app = express()
const port = process.env.NODE_ENV === 'production'
             ? process.env.BACKEND_PROD_PORT
             : process.env.BACKEND_DEV_PORT;

const deviceInfoRouter = require('./routes/deviceInfo')
const serversRouter = require('./routes/servers')
const deviceLinkRequestRouter = require('./routes/deviceLinkRequest')
const deviceRouter = require('./routes/device')

// Only accept requests comming from client ip and port
 app.use(cors({origin : process.env.NODE_ENV === 'production'
   ? `http://${process.env.CLIENT_PROD_IP}:${CLIENT_PROD_PORT}`
   : `http://${process.env.CLIENT_DEV_IP}:${CLIENT_DEV_PORT}`
 }))

app.use(bodyParser.json())

app.use('/deviceInfo', deviceInfoRouter)
app.use('/servers', serversRouter)
app.use('/deviceLinkRequest', deviceLinkRequestRouter)
app.use('/device', deviceRouter)

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
