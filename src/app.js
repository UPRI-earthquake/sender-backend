const express = require('express')
const cors = require('cors')
const bodyParser = require('body-parser')
const swaggerJsDoc = require('swagger-jsdoc')
const swaggerUi = require('swagger-ui-express')

const app = express()

const options = {
  swaggerDefinition: {
    openapi: '3.0.0',
    info: {
      title: 'rShake APIs',
      version: '1.0.0',
      description: 'These are the API endpoints used for rshake-backend',
    },
  },
  apis: ['./src/routes/*.js'], // Path to the API routes
};

const specs = swaggerJsDoc(options);

app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(specs));

const port = process.env.NODE_ENV === 'production'
             ? process.env.BACKEND_PROD_PORT
             : process.env.BACKEND_DEV_PORT;

const deviceInfoRouter = require('./routes/deviceInfo')
const serversRouter = require('./routes/servers')
const deviceLinkRequestRouter = require('./routes/deviceLinkRequest')
const streamRouter = require('./routes/stream.route')

// Only accept requests comming from client ip and port
 app.use(cors({origin : process.env.NODE_ENV === 'production'
   ? `http://${process.env.CLIENT_PROD_IP}:${process.env.CLIENT_PROD_PORT}`
   : `http://${process.env.CLIENT_DEV_IP}:${process.env.CLIENT_DEV_PORT}`
 }))

app.use(bodyParser.json())

app.use('/deviceInfo', deviceInfoRouter)
app.use('/servers', serversRouter)
app.use('/deviceLinkRequest', deviceLinkRequestRouter)
app.use('/stream', streamRouter)

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
