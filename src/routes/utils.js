const fs = require('fs')

function read_network() {
  try {
    const network = fs.readFileSync('/opt/settings/sys/NET.txt', 'utf8');
    return network.trim();
  } catch (error) {
    // log and move on
    console.log(error)
  }
  return '';
}

function read_station() {
  try {
    const station = fs.readFileSync('/opt/settings/sys/STN.txt', 'utf8');
    return station.trim();
  } catch (error) {
    // log and move on
    console.log(error)
  }
  return '';
}
// A function for getting the device streamId from rshake
function generate_streamId() {
  let network = read_network() 
  let station = read_station() 

  return `${network}_${station}_.*/MSEED` // based on RingServer streamID format
}

module.exports = {
  read_network,
  read_station,
  generate_streamId
};
