const express = require('express');
const router = express.Router();
const bodyParser = require('body-parser');
const path = require('path');
const { spawn } = require('child_process');

router.use(bodyParser.json())

// POST endpoint (/stream) to execute a slink2dali childprocess from nodejs
router.route('/stream').post( async (req, res) => {
    console.log('POST Request sent on /device/stream endpoint')

    try {
        const command = `${process.env.SLINK2DALIPATH}/slink2dali`;
        const options = `-vvv -S GE_TOLI2 geofon.gfz-potsdam.de:18000 localhost:18000`.split(' ');

        // Execute the command using spawn
        const childProcess = spawn(command, options);
        
        // Listen for 'error' event from the child process
        childProcess.on('error', (error) => {
            console.error(`Error executing command: ${error}`);
            // Handle the error and send an appropriate response
        });

        // Listen for 'close' event from the child process
        childProcess.on('close', (code, signal) => {
            console.log(`Child process closed with code ${code} and signal ${signal}`);
            // Handle the command output or completion here
            // Send a success response
            // res.status(200).json({ message: 'Command executed successfully' });
        });

        // Listen for 'exit' event from the child process
        childProcess.on('exit', (code, signal) => {
            console.log(`Child process exited with code ${code} and signal ${signal}`);
        });

        // Listen for 'stdout' event from the child process
        childProcess.stdout.on('data', (data) => {
            console.log(`Command output: ${data}`);
        });

        // Listen for 'stderr' event from the child process
        childProcess.stderr.on('data', (data) => {
            console.error(`Command error: ${data}`);
        });

        res.status(200).json({ message: 'Command executed successfully' });
    } catch (error) {
        console.error(`Error executing command: ${error}`);
        // Handle the error and send an appropriate response
        res.status(500).json({ error: 'Internal Server Error' });
    }
})

module.exports = router;