const express = require('express');
const sshController = require('../controllers/sshController');
const { validateExecuteCommand } = require('../middleware/validators');

const router = express.Router();

/**
 * @route POST /api/v1/execute
 * @desc Execute a command on the SSH jumphost
 * @access Public
 */
router.post('/execute', validateExecuteCommand, sshController.executeCommand);

module.exports = router; 