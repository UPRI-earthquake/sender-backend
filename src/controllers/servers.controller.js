const fs = require('fs').promises;

async function getServersList(req, res) {
  try {
    const filePath = `${process.env.LOCALDBS_DIRECTORY}/servers.json`;
    const jsonString = await fs.readFile(filePath, 'utf-8');
    const data = JSON.parse(jsonString);
    
    console.log(data);
    res.status(200).json(data);
  } catch (err) {
    console.error(`Error reading servers.js: ${err}`);
    res.status(500).json({ message: 'Error getting servers list' });
  }
}

module.exports = { getServersList };
