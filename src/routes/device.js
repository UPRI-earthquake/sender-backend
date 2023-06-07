const express = require('express');
const router = express.Router();
const { spawn, exec } = require('child_process');
const fs = require('fs')
const bodyParser = require('body-parser')
const { getChildProcesses, checkChildProcessStatus, updateChildProcessStatus } = require('./childProcess.module')

router.use(bodyParser.json())

let childProcesses = null;

async function populateChildProcesses() {
    try {
        childProcesses = await getChildProcesses();
        return childProcesses;
    } catch (error) {
        console.error(`Error getting child processes: ${error}`);
    }
}

// Middleware function to check the streaming status to the specified server url; status should not be 'Streaming'
async function childProcessStatusCheck(req, res, next) {
    const childProcessStatus = await checkChildProcessStatus(req.body.url);
    if (!childProcessStatus) {
        // Child process is already streaming
        return res.status(409).json({ message: 'Child process is already streaming in the specified URL' });
    }

    next(); // Proceed to the next middleware/route handler
}


// POST endpoint (/stream/start) to execute a slink2dali childprocess from nodejs
router.route('/stream/start').post(childProcessStatusCheck, async (req, res) => {
    console.log('POST Request sent on /device/stream endpoint')
    let childProcess = null;
    childProcesses = await populateChildProcesses(); // Call the async function to populate the childProcesses array

    try {
        // TODO: Add necessary options to be sent as arguments of the slink2dali (i.e. token, target ringserver etc.)
        const command = `${process.env.SLINK2DALIPATH}/slink2dali`;
        const net_sta = 'GE_TOLI2'; // CHANGE THIS. This info should come from deviceInfo.json
        const sender_slink2dali = 'geofon.gfz-potsdam.de:18000'; // CHANGE THIS
        const receiver_ringserver = req.body.url;
        const options = ['-vvv', '-S', net_sta, sender_slink2dali, receiver_ringserver];

        // Execute the command using spawn
        childProcess = spawn(command, options);

        let hasError = false; // Flag to track if error occurred

        // Listen for 'error' event from the child process
        childProcess.on('error', (error) => {
            console.error(`Error executing command: ${error}`);
            // Handle the error and send an appropriate response
            hasError = true;
        });

        // Listen for 'close' event from the child process
        childProcess.on('close', (code, signal) => {
            console.log(`Child process closed with code ${code} and signal ${signal}`);
        });

        // Listen for 'exit' event from the child process
        childProcess.on('exit', async (code, signal) => {
            console.log(`Child process exited with code ${code} and signal ${signal}`);

            if (hasError) {
                // Cleanup functions: 
                childProcess.kill(); // Terminate the child process
                childProcesses = await updateChildProcessStatus(receiver_ringserver, null, 'Not Streaming'); // Update the status of childProcess from the childProcesses array to 'Not Streaming'
            }
        });

        // Listen for 'stdout' event from the child process
        childProcess.stdout.on('data', (data) => {
            console.log(`Command output: ${data}`); // Log slink2dali output 

            // Listen for 'error' logs in slink2dali
            if (data.includes('error')) {
                console.error('Error encountered in slink2dali logs');
                // Set the error flag to true
                hasError = true;
            }
        });

        // Listen for 'stderr' event from the child process
        childProcess.stderr.on('data', (data) => {
            console.error(`Command error: ${data}`);
        });

        childProcesses = await updateChildProcessStatus(receiver_ringserver, childProcess, 'Streaming'); // Update the childProcess status in the array to 'streaming'

        res.status(200).json({ message: 'Child process spawned successfully' });
    } catch (error) {
        console.error(`Error spawning slink2dali: ${error}`);
        if (childProcess) {
            childProcess.kill();
        }
        // Handle the error and send an appropriate response
        res.status(500).json({ error: 'Error spawning child process' });
    }
})


router.post('/stream/stop', async (req, res) => {
    console.log('POST Request sent on /stream/stop endpoint');

    try {
        const { url, toggleValue } = req.body;

        // Find the child process with the specified URL
        const childProcessObj = childProcesses.find((item) => item.url === url);

        if (childProcessObj) {
            const pid = childProcessObj.childProcess;

            // Kill the child process using the saved process ID
            exec(`kill ${pid}`, (error, stdout, stderr) => {
                if (error) {
                    console.error(`Error stopping child process: ${error}`);
                    res.status(500).json({ message: 'Internal Server Error' });
                } else {
                    // Remove the child process from the array
                    childProcesses = childProcesses.filter((item) => item.childProcess !== pid);
                    res.status(200).json({ message: 'Child process stopped successfully' });
                }
            });
        } else {
            res.status(404).json({ message: 'Child process not found' });
        }
    } catch (error) {
        console.error(`Error stopping child process: ${error}`);
        // Handle the error and send an appropriate response
        res.status(500).json({ message: 'Internal Server Error' });
    }
});

router.get('/stream/status', async (req, res) => {
    childProcesses = await populateChildProcesses();
    console.log(childProcesses)
    res.status(200).json({ message: 'Get Streams Status Success', payload: childProcesses })
})

module.exports = router;
