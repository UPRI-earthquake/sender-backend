// import app from './app'
const app = require('./app')
const { initializeStreamsObject, spawnSlink2dali } = require('./controllers/stream.controller')
require('dotenv').config()

// Asynchronous function for initializing streamsObject dictionary, then start streaming on each supplied url.
async function init() {
  try {
    let streamsObject = await initializeStreamsObject();

    for (const url in streamsObject) {
      if (streamsObject.hasOwnProperty(url)) {
        await spawnSlink2dali(url);
      }
    }
  } catch (error) {
    console.error('Error occurred:', error);
  }
}

// Call the main function
init();


const port = process.env.NODE_ENV === 'production'
  ? process.env.BACKEND_PROD_PORT
  : process.env.BACKEND_DEV_PORT;

const ip = process.env.NODE_ENV === 'production'
  ? process.env.BACKEND_PROD_IP
  : process.env.BACKEND_DEV_IP;

app.listen(port, ip, () => {
  console.log('App listening on port: ' + port)
})
