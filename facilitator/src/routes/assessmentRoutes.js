const express = require('express');
const assessmentController = require('../controllers/assessmentController');

const router = express.Router();

/**
 * @route GET /api/v1/assements
 * @desc Get all assessments
 * @access Public
 */
router.get('/', assessmentController.getAssessments);

module.exports = router; 