const express = require('express')
const cors = require('cors')
const bodyParser = require('body-parser')
const swaggerJsDoc = require('swagger-jsdoc')
const swaggerUi = require('swagger-ui-express')
const fs = require('fs')
const metricsService = require('./services/metrics.service')

const structuredLogsEnabled = String(process.env.SENDER_STRUCTURED_LOGS || 'false').trim().toLowerCase() === 'true';

function emitStructuredLog(eventType, payload = {}) {
  if (!structuredLogsEnabled) return;
  const entry = {
    ts: new Date().toISOString(),
    event: eventType,
    ...payload,
  };
  console.log(JSON.stringify(entry));
}

const app = express()

if (process.env.NODE_ENV !== 'production' && process.env.NODE_ENV !== 'test') {
  const options = {
    swaggerDefinition: {
      openapi: '3.0.0',
      info: {
        title: 'sender-backend APIs',
        version: '1.0.0',
        description: 'These are the API endpoints used for sender-backend',
      },
    },
    apis: ['./src/routes/*.js'], // Path to the API routes
  };

  const specs = swaggerJsDoc(options);
  const swaggerJson = JSON.stringify(specs, null, 2); // Convert to JSON with 2 spaces as indent
  fs.writeFileSync('./docs/sender-backend-api-docs.json', swaggerJson, 'utf8'); // Write the JSON data to a file (e.g., api-docs.json)
  app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(specs));
}

const deviceRouter = require('./routes/device.route')
const serversRouter = require('./routes/servers.route')
const streamRouter = require('./routes/stream.route')
const healthRouter = require('./routes/health.route')

// Accept all sources of connection requests. This is to accommodate requests coming from both rs.local:3000 and from the rshake device ip address
app.use(cors())

app.use(bodyParser.json())

app.use((req, res, next) => {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const elapsedNs = process.hrtime.bigint() - start;
    const durationMs = Number(elapsedNs) / 1e6;
    const requestPath = req.path || req.originalUrl || '/';
    metricsService.recordHttpRequest({
      method: req.method,
      path: requestPath,
      statusCode: res.statusCode,
      durationMs,
    });
    emitStructuredLog('http.request', {
      method: req.method,
      path: requestPath,
      statusCode: res.statusCode,
      durationMs: Number(durationMs.toFixed(1)),
    });
  });
  next();
});

app.use('/device', deviceRouter)
app.use('/servers', serversRouter)
app.use('/stream', streamRouter)
app.use('/health', healthRouter)

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
