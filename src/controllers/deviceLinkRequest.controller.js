const fs = require('fs').promises;
const deviceLinkService = require('../services/deviceLinkRequest.service')
const Joi = require('joi')

const accountValidationSchema = Joi.object({
  username: Joi.string().required(),
  password: Joi.string().pattern(new RegExp('^[a-zA-Z0-9]{6,30}$')).required(),
});

const linkDevice = async (req, res) => {
  try {
    // Validate input
    const { error } = accountValidationSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ status: 400, message: error.details[0].message });
    }

    let token = await deviceLinkService.checkAuthToken(); // Check auth token from file
    if (!token) {
      token = await deviceLinkService.requestAuthToken(req.body.username, req.body.password) // Request accessToken in ehub-backend
    }

    // Link the device and get device information
    const deviceInfo = await deviceLinkService.requestLinking(token);
    const deviceInfoPath = `${process.env.LOCALDBS_DIRECTORY}/deviceInfo.json`;
    await fs.writeFile(deviceInfoPath, JSON.stringify(deviceInfo));

    return res.status(200).json({
      status: 200,
      message: 'Successfully Requested Linking to W1',
    });
  } catch (error) {
    // TODO: Add clean-up function that restores local file stores if an error is encountered while linking
    if (error.response) {
      return res.status(error.response.status).json({
        status: error.response.status,
        message: "Error from earthquake-hub: " + error.response.data.message,
      });
    } else {
      console.log(error)
      return res.status(500).json({
        status: 500,
        message: error
      });
    }
  }
};


module.exports = { linkDevice };