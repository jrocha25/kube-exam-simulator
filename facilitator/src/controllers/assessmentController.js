const fs = require('fs');
const path = require('path');
const logger = require('../utils/logger');

/**
 * Get all assessments
 * @param {Object} req - Express request object
 * @param {Object} res - Express response object
 */
async function getAssessments(req, res) {
  logger.info('Received request to get all assessments');
  
  try {
    const labsFilePath = path.join(process.cwd(), 'assets', 'exams', 'labs.json');
    logger.info(`Reading labs from file: ${labsFilePath}`);
    
    if (!fs.existsSync(labsFilePath)) {
      logger.error(`Labs file not found at path: ${labsFilePath}`);
      return res.status(500).json({
        error: 'Labs data not available',
        message: 'Could not find labs data file'
      });
    }
    
    const labsData = fs.readFileSync(labsFilePath, 'utf8');
    const labs = JSON.parse(labsData);
    
    logger.info(`Successfully retrieved ${labs.labs ? labs.labs.length : 0} labs`);
    
    return res.status(200).json(labs.labs || []);
  } catch (error) {
    logger.error('Error reading labs data', { error: error.message });
    return res.status(500).json({
      error: 'Failed to retrieve labs data',
      message: error.message
    });
  }
}

module.exports = {
  getAssessments
}; 