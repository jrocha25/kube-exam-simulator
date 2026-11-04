const remoteDesktopService = require('../services/remoteDesktopService');
const logger = require('../utils/logger');

/**
 * Controller for handling remote desktop operations
 */
class RemoteDesktopController {
    /**
     * Copy content to remote desktop clipboard
     * @param {Object} req - Express request object
     * @param {Object} res - Express response object
     */
    async copyToClipboard(req, res) {
        try {
            const { content } = req.body;
            
            if (!content) {
                return res.sendStatus(400);
            }

            await remoteDesktopService.copyToClipboard(content);
            res.sendStatus(204);
            
        } catch (error) {
            logger.error('Error in copyToClipboard controller', {
                error: error.message
            });
            res.sendStatus(500);
        }
    }
}

module.exports = new RemoteDesktopController(); 