const sshService = require('../services/sshService');
const logger = require('../utils/logger');

/**
 * Execute a command on the SSH jumphost
 * @param {Object} req - Express request object
 * @param {Object} res - Express response object
 */
async function executeCommand(req, res) {
  try {
    const { command } = req.body;
    
    if (!command) {
      logger.warn('Execute command request with missing command field');
      return res.status(400).json({ 
        error: 'Missing required field: command' 
      });
    }
    
    logger.info('Received execute command request', { command });
    
    const result = await sshService.executeCommand(command);
    
    logger.info('Command executed successfully', { 
      exitCode: result.exitCode,
      stdout: result.stdout.substring(0, 100) + (result.stdout.length > 100 ? '...' : '')
    });
    
    return res.status(200).json(result);
  } catch (error) {
    logger.error('Error executing command', { error: error.message });
    
    return res.status(500).json({ 
      error: 'Failed to execute command', 
      message: error.message 
    });
  }
}

module.exports = {
  executeCommand
}; 