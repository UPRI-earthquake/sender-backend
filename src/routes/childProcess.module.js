const fs = require('fs')
const path = require('path')

let childProcesses = [];

async function getChildProcesses() {
	try {
		const localFileStoreDir = path.resolve(__dirname, '../localDBs');
		const jsonString = await fs.promises.readFile(`${localFileStoreDir}/servers.json`, 'utf-8');
		const serversList = JSON.parse(jsonString);
		
		// Modify each server object and add additional parameters
    const modifiedServers = serversList.map(server => ({
      ...server,
      childProcess: null,
      status: 'Not Streaming'
    }));

    childProcesses.push(...modifiedServers); // Push the modified servers array to the childProcesses array
		return childProcesses;
	} catch (error) {
		console.log(`Error reading file: ${error}`)
		return;
	}
}

module.exports = getChildProcesses;