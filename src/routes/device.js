const express = require('express');
const router = express.Router();
const { spawn, exec } = require('child_process');
const fs = require('fs')
const bodyParser = require('body-parser')
const { generate_streamId } = require('./utils');

router.use(bodyParser.json())

let childProcesses = []; // Global Array to store child processes

// A function that changes the isAllowedToStream parameter from servers.json file
async function setIsAllowedToStream(url, toggleValue) {
    // Read data from servers.json file
    const jsonString = await fs.promises.readFile('src/localDBs/servers.json', 'utf-8');
    const existingServers = JSON.parse(jsonString);

    // Find the server with the matching URL from servers.json file
    const server = existingServers.find((item) => item.url === url);

    if ( !server) {
      throw new Error('Target server URL not found on the local file store')
    }

    // Update the isAllowedToStream parameter depending on the toggleValue from frontend
    if (toggleValue === true) {
        server.isAllowedToStream = true;
    } else { server.isAllowedToStream = false; }

    // Save the updated servers array back to the json file
    await fs.promises.writeFile('src/localDBs/servers.json', JSON.stringify(existingServers));

}

// POST endpoint (/stream/start) to execute a slink2dali childprocess from nodejs
router.route('/stream/start').post(async (req, res) => {
    console.log('POST Request sent on /device/stream endpoint')
    let childProcess = null;

    try {
        // TODO: Check first if there is a slink2dali sending request to the target ringserver

        // TODO: Add necessary options to be sent as arguments of the slink2dali (i.e. token, target ringserver etc.)
        const command = `${process.env.SLINK2DALIPATH}/slink2dali`;
        const network = read_network()
        const station = read_station()
        const net_sta = `${network}_${station}`; 
        const sender_slink2dali = 'docker-host:18000';
        const receiver_ringserver = req.body.url;
        const options = ['-vvv', '-S', net_sta , sender_slink2dali, receiver_ringserver];

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
        childProcess.on('exit', async(code, signal) => {
            console.log(`Child process exited with code ${code} and signal ${signal}`);

            if (hasError) {
                // Cleanup functions
                // Terminate the child process if an error occurred during execution
                childProcess.kill();

                // Update the status of childProcess from the childProcesses array
                const index = childProcesses.findIndex((item) => item.childProcess === childProcess.pid);
                if (index !== -1) {
                    childProcesses[index].status = 'Not Streaming';
                    console.log(`Child process [ ${childProcess.pid} ] status updated`);
                    console.log(childProcesses)
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
        childProcesses.push({ childProcess: childProcess.pid, url: receiver_ringserver , status: 'Streaming'});
        console.log(childProcesses);

        await setIsAllowedToStream(req.body.url, req.body.toggleValue); // Call the function that toggles the parameter isAllowedToStream

        res.status(200).json({ message: 'Child process spawned successfully' });
    } catch (error) {
        console.error(`In starting slink2dali: ${error}`);
        if(childProcess){
          childProcess.kill();
        }
        // Handle the error and send an appropriate response
        res.status(500).json({ error: 'Internal Server Error' });
    }
})


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
    res.status(200).json({ message: 'Get Streams Status Success', payload: childProcesses })
    console.log('Success')
})

module.exports = router;
