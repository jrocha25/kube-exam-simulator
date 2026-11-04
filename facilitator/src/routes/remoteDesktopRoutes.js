const express = require('express');
const router = express.Router();
const remoteDesktopController = require('../controllers/remoteDesktopController');

/**
 * @route   POST /api/remote-desktop/clipboard
 * @desc    Copy content to remote desktop clipboard
 * @access  Private
 */
router.post('/clipboard', remoteDesktopController.copyToClipboard);

module.exports = router; 