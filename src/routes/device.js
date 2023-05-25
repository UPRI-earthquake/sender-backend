const express = require('express');
const router = express.Router();
const { spawn, exec } = require('child_process');
const fs = require('fs')
const bodyParser = require('body-parser')

router.use(bodyParser.json())

let childProcesses = []; // Global Array to store child processes

// A function that changes the isAllowedToStream parameter from servers.json file
async function setIsAllowedToStream(url, toggleValue) {
    let retVal = '';
    try {
        // Read data from servers.json file
        const jsonString = await fs.promises.readFile('src/localDBs/servers.json', 'utf-8');
        const existingServers = JSON.parse(jsonString);

        // Find the server with the matching URL from servers.json file
        const server = existingServers.find((item) => item.url === url);

        if (server) {
            // Update the isAllowedToStream parameter depending on the toggleValue from frontend
            if (toggleValue === true) {
                server.isAllowedToStream = true;
            } else { server.isAllowedToStream = false; }

            // Save the updated servers array back to the json file
            await fs.promises.writeFile('src/localDBs/servers.json', JSON.stringify(existingServers));
            // next();
            retVal = 0;
        } else {
            // Send a response indicating the URL was not found in the file
            // res.status(404).json({ message: 'Server URL not found' });
            retVal = 'Error: Server URL not found on the local file store';
            // return;
        }
    } catch (error) {
        console.error(`Error updating server URL: ${error}`);
        // res.status(500).json({ message: 'Internal Server Error' });
        retVal = 'Error: Internal Server Error'
        // return;
    }

    return retVal;
}

// POST endpoint (/stream/start) to execute a slink2dali childprocess from nodejs
router.route('/stream/start').post(async (req, res) => {
    console.log('POST Request sent on /device/stream endpoint')

    try {
        // TODO: Check first if there is a slink2dali sending request to the target ringserver

        // TODO: Add necessary options to be sent as arguments of the slink2dali (i.e. token, target ringserver etc.)
        const command = `${process.env.SLINK2DALIPATH}/slink2dali`;
        const net_sta = 'GE_TOLI2'; // CHANGE THIS
        const sender_slink2dali = 'geofon.gfz-potsdam.de:18000'; // CHANGE THIS
        const receiver_ringserver = req.body.url; // CHANGE THIS
        const options = ['-vvv', '-S', net_sta , sender_slink2dali, receiver_ringserver];

        // Execute the command using spawn
        const childProcess = spawn(command, options);

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
        childProcess.on('exit', async(code, signal) => {
            console.log(`Child process exited with code ${code} and signal ${signal}`);

            if (hasError) {
                // Cleanup functions
                // Terminate the child process if an error occurred during execution
                childProcess.kill();
                
                // Removes the childProcess from the childProcesses array
                const index = childProcesses.findIndex((item) => item.childProcess === childProcess.pid);
                if (index !== -1) {
                    childProcesses.splice(index, 1);
                    console.log(`Child process ${childProcess.pid} removed from the array`);
                }

                // Revert back the isAllowedToStream parameter
                setIsAllowedToStream(req.body.url, 'false')
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

        // Add the child process to the array if no error occurred
        childProcesses.push({ childProcess: childProcess.pid, url: receiver_ringserver });
        console.log(childProcesses);

        const response = await setIsAllowedToStream(req.body.url, req.body.toggleValue); // Call the function that toggles the parameter isAllowedToStream
        if (response != 0) {
            console.log(response)
            childProcess.kill();
        }

        // Add 2-second delay to listen for slink2dali error before sending json response
        if (!hasError) {
            setTimeout(() => {
                res.status(200).json({ message: 'Command executed successfully' });
            }, 2000);
        } else {
            setTimeout(() => {
                res.status(500).json({ message: 'Error encountered on slink2dali' });
            }, 2000);
        }
        
    } catch (error) {
        console.error(`Error executing command: ${error}`);
        // Handle the error and send an appropriate response
        res.status(500).json({ error: 'Internal Server Error' });
    }
})


// Function to remove a child process from the childProcesses array
function removeChildProcess(pid) {
    childProcesses = childProcesses.filter((item) => item.childProcess !== pid);
}

router.post('/stream/stop', async (req, res) => {
    console.log('POST Request sent on /stream/stop endpoint');
    console.log(childProcesses)

    try {
        const { url, toggleValue } = req.body;

        // Update the isAllowedToStream parameter in json file
        setIsAllowedToStream(url, toggleValue);

        // Find the child process with the specified URL
        const childProcessObj = childProcesses.find((item) => item.url === url);

        if (childProcessObj) {
            const pid = childProcessObj.childProcess;

            // Kill the child process using the process ID
            exec(`kill ${pid}`, (error, stdout, stderr) => {
                if (error) {
                    console.error(`Error stopping child process: ${error}`);
                    res.status(500).json({ message: 'Internal Server Error' });
                } else {
                    // Remove the child process from the array
                    removeChildProcess(pid);
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

module.exports = router;