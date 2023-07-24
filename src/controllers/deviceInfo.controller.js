const fs = require('fs').promises;

async function getDeviceInfo(req, res) {
  try {
    const filePath = `${process.env.LOCALDBS_DIRECTORY}/deviceInfo.json`;
    const defaultDeviceInfo = {
      network: null,
      station: null,
      location: null,
      channel: null,
      elevation: null,
      streamId: null,
    };

    let data = { deviceInfo: defaultDeviceInfo };

    const jsonString = await fs.readFile(filePath, 'utf-8');
    data = JSON.parse(jsonString);

    console.log(data.deviceInfo);
    res.status(200).json(data.deviceInfo);
  } catch (error) {
    console.error(`Error reading file: ${error}`);
    res.status(500).json({ message: 'Error reading file' });
  }
}

module.exports = { getDeviceInfo };
