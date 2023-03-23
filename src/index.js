const express = require('express')
const cors = require('cors')
const app = express()
const bodyParser = require('body-parser')
const port = 5001 //Specify the port, if necessary

const accountInfoRouter = require('./routes/accountInfo')
const deviceInfoRouter = require('./routes/deviceInfo')
const serversRouter = require('./routes/servers')

app.use(cors())

app.use(bodyParser.json())

app.use('/accountInfo', accountInfoRouter)
app.use('/deviceInfo', deviceInfoRouter)
app.use('/servers', serversRouter)

  
app.listen(port, () => {
    console.log('App listening on port: ' + port)
})