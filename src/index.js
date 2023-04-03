const express = require('express')
const cors = require('cors')
const bodyParser = require('body-parser')
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

app.listen(port, () => {
    console.log('App listening on port: ' + port)
})