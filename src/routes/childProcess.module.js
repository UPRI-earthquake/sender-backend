const fs = require('fs')
const path = require('path')

let childProcesses = [];

async function getChildProcesses() {
	if (childProcesses.length > 0) { // childProcesses object is not null
		return childProcesses;
	} else { // childProcesses object initialization
		try {
			const localFileStoreDir = path.resolve(__dirname, '../localDBs');
			const jsonString = await fs.promises.readFile(`${localFileStoreDir}/servers.json`, 'utf-8');
			const serversList = JSON.parse(jsonString);
	
			// Create a map to keep track of unique URLs
			const urlMap = new Map();
	
			// Iterate over the serversList and update the childProcesses object
			childProcesses = serversList.reduce((result, server) => {
				const { url } = server;
				if (!urlMap.has(url)) {
					// Add the server to childProcesses object if it's a unique URL
					result.push({
						...server,
						childProcess: null,
						status: 'Not Streaming'
					});
					urlMap.set(url, true); // Mark the URL as added to the map
				}
				return result;
			}, []);
	
			return childProcesses;
		} catch (error) {
			console.log(`Error reading file: ${error}`);
			return [];
		}
	}
}

childProcesses = getChildProcesses();

async function checkChildProcessStatus(url) {
	const childProcess = await childProcesses.find(server => server.url === url);
	console.log(`MODULE: ${JSON.stringify(childProcess)}`)
	if (childProcess.status != 'Streaming') { // Child process' status IS NOT 'Streaming'
		return childProcesses; // return childProcesses object
	} else {
		return; // return null
	}
}

async function updateChildProcessStatus(url, childProcess, status) {
  const stream = await childProcesses.find(server => server.url === url);
  if (stream) {
		stream.childProcess = childProcess;
    stream.status = status;
  }
	return childProcesses;
}

async function addChildProcess(hostName, url) {
	const process = {
		url: url,
		hostName: hostName,
		childProcess: null,
		status: 'Not Streaming'
	}
  childProcesses.push(process);
}


module.exports = {
  getChildProcesses,
	checkChildProcessStatus,
  updateChildProcessStatus,
	addChildProcess
};