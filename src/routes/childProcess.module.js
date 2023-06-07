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

function checkChildProcessStatus(url) {
	const childProcess = childProcesses.find(server => server.url === url);
  return childProcess.status; // return status of the specified url
}

function updateChildProcessStatus(url, status) {
  const childProcess = childProcesses.find(server => server.url === url);
  if (childProcess) {
    childProcess.status = status;
  }
}


module.exports = {
  getChildProcesses,
	checkChildProcessStatus,
  updateChildProcessStatus
};