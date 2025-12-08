const express = require('express');
const router = express.Router();
const bodyParser = require('body-parser');
const healthController = require('../controllers/health.controller');

router.use(bodyParser.json());

router.get('/network', healthController.networkHealth);
router.get('/time', healthController.timeHealth);

module.exports = router;
