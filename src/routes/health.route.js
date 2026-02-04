const express = require('express');
const router = express.Router();
const bodyParser = require('body-parser');
const healthController = require('../controllers/health.controller');

router.use(bodyParser.json());

/**
 * @swagger
 * /health/network:
 *   get:
 *     summary: Check network reachability for W1 and configured ringservers
 *     tags:
 *       - Health
 *     responses:
 *       200:
 *         description: Network health check complete
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.HEALTH_NETWORK_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Network health check complete"
 *                 payload:
 *                   type: object
 *                   properties:
 *                     target:
 *                       type: object
 *                     dns:
 *                       type: object
 *                     tcp:
 *                       type: object
 *                     https:
 *                       type: object
 *                     ringservers:
 *                       type: array
 *                       items:
 *                         type: object
 */
router.get('/network', healthController.networkHealth);

/**
 * @swagger
 * /health/time:
 *   get:
 *     summary: Verify NTP reachability and clock offset
 *     tags:
 *       - Health
 *     responses:
 *       200:
 *         description: Time synchronization check complete
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.HEALTH_TIME_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Time synchronization check complete"
 *                 payload:
 *                   type: object
 *                   properties:
 *                     target:
 *                       type: object
 *                     serverDate:
 *                       type: string
 *                       nullable: true
 *                     offsetMs:
 *                       type: number
 *                       nullable: true
 *                     roundTripMs:
 *                       type: number
 *                       nullable: true
 *                     attempts:
 *                       type: array
 *                       items:
 *                         type: object
 *       500:
 *         description: Time synchronization check failed
 */
router.get('/time', healthController.timeHealth);

/**
 * @swagger
 * /health/resources:
 *   get:
 *     summary: Read host disk and CPU usage snapshot
 *     tags:
 *       - Health
 *     responses:
 *       200:
 *         description: Resource usage snapshot
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: number
 *                   example: responseCodes.HEALTH_RESOURCES_SUCCESS
 *                 message:
 *                   type: string
 *                   example: "Resource usage snapshot"
 *                 payload:
 *                   type: object
 *                   properties:
 *                     disk:
 *                       type: object
 *                       properties:
 *                         path:
 *                           type: string
 *                         totalBytes:
 *                           type: number
 *                         usedBytes:
 *                           type: number
 *                         freeBytes:
 *                           type: number
 *                         usedPercent:
 *                           type: number
 *                     cpu:
 *                       type: object
 *                       properties:
 *                         cores:
 *                           type: number
 *                         usagePercent:
 *                           type: number
 *                           nullable: true
 *                         loadAverage:
 *                           type: array
 *                           items:
 *                             type: number
 *       500:
 *         description: Unable to read host resource usage
 */
router.get('/resources', healthController.resourcesHealth);

module.exports = router;
