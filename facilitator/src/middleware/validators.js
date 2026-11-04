const Joi = require('joi');
const logger = require('../utils/logger');

/**
 * Validate the execute command request
 */
const validateExecuteCommand = (req, res, next) => {
  const schema = Joi.object({
    command: Joi.string().required()
  });
  
  const { error } = schema.validate(req.body);
  
  if (error) {
    logger.warn('Invalid execute command request', { error: error.message });
    return res.status(400).json({ error: error.message });
  }
  
  next();
};

/**
 * Validate the create exam request
 */
const validateCreateExam = (req, res, next) => {
  // This is a placeholder validation - will be implemented fully later
  const schema = Joi.object({
    // Add exam schema validation later
  }).unknown(true);
  
  const { error } = schema.validate(req.body);
  
  if (error) {
    logger.warn('Invalid create exam request', { error: error.message });
    return res.status(400).json({ error: error.message });
  }
  
  next();
};

/**
 * Validate the evaluate exam request
 */
const validateEvaluateExam = (req, res, next) => {
  // TODO: Implement this
  next();
};

/**
 * Validate exam events request
 * @param {Object} req - Express request object
 * @param {Object} res - Express response object
 * @param {Function} next - Express next middleware function
 */
const validateExamEvents = (req, res, next) => {
  const { events } = req.body;

  if (!events || typeof events !== 'object') {
    return res.status(400).json({
      error: 'Bad Request',
      message: 'Request body must include events field as an object'
    });
  }

  next();
};

module.exports = {
  validateExecuteCommand,
  validateCreateExam,
  validateEvaluateExam,
  validateExamEvents
}; 