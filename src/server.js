// import app from './app'
const app = require('./app')
require('dotenv').config()

const port = process.env.NODE_ENV === 'production'
             ? process.env.BACKEND_PROD_PORT
             : process.env.BACKEND_DEV_PORT;

const ip = process.env.NODE_ENV === 'production'
             ? process.env.BACKEND_PROD_IP
             : process.env.BACKEND_DEV_IP;
             
app.listen(port,ip, () => {
    console.log('App listening on port: ' + port)
})
