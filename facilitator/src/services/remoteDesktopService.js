const axios = require('axios');
const logger = require('../utils/logger');
const config = require('../config');

class RemoteDesktopService {
    constructor() {
        this.baseUrl = `http://${config.remoteDesktop.host}:${config.remoteDesktop.port}`;
    }

    /**
     * Restart the VNC session
     * @returns {Promise<void>}
     */
    async restartVncSession() {
        try {
            logger.info('Restarting VNC session');
            await axios.get(`${this.baseUrl}/restart-vnc-session`);
            logger.info('VNC session restart initiated successfully');
        } catch (error) {
            logger.error('Failed to restart VNC session', {
                error: error.response?.data?.error || error.message
            });
            throw new Error('Failed to restart VNC session');
        }
    }

    /**
     * Copy content to remote desktop clipboard
     * @param {string} content - Content to copy to clipboard
     * @returns {Promise<void>}
     */
    async copyToClipboard(content) {
        try {
            if (!content) {
                throw new Error('Clipboard content is required');
            }

            await axios.post(`${this.baseUrl}/clipboard-paste`, {
                content: content
            }, {
                headers: {
                    'Content-Type': 'application/json'
                }
            });
        } catch (error) {
            logger.error('Failed to copy content to clipboard', {
                error: error.response?.data?.error || error.message
            });
            throw new Error('Failed to copy content to clipboard');
        }
    }
}

// Export singleton instance
module.exports = new RemoteDesktopService(); 