// import app from './app'
const app = require('./app')
const { createLocalFileStoreDir } = require('./services/utils')
const { initializeStreamsObject, spawnSlink2dali } = require('./controllers/stream.utils')

// Asynchronous function for:
// 1. creating local file store,
// 2. initializing streamsObject dictionary, 
// 3. then start streaming on each supplied url.
async function init() {
  try {
    await createLocalFileStoreDir();
    let streamsObject = await initializeStreamsObject();
    console.log(streamsObject)

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
