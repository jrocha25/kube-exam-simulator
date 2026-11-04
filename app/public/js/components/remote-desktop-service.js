/**
 * Remote Desktop Service
 * Handles remote desktop connection and management
 */
import { getVncInfo } from './exam-api.js';

// Connect to VNC
function connectToRemoteDesktop(vncFrame, statusCallback) {
    if (statusCallback) {
        statusCallback('Connecting to Remote Desktop...', 'info');
    }
    
    // Get VNC server info from API
    return getVncInfo()
        .then(data => {
            console.log('Remote Desktop info:', data);
            
            // Create the VNC URL with proper parameters
            const vncUrl = `/vnc-proxy/?autoconnect=true&resize=scale&show_dot=true&reconnect=true&password=${data.defaultPassword}`;
            
            // Set the iframe source to the VNC URL
            vncFrame.src = vncUrl;
            if (statusCallback) {
                statusCallback('Connected to Session', 'success');
            }
            return vncUrl;
        })
        .catch(error => {
            console.error('Error connecting to Remote Desktop:', error);
            if (statusCallback) {
                statusCallback('Failed to connect to Remote Desktop. Retrying...', 'error');
            }
            // Return a promise that will retry
            return new Promise(resolve => {
                setTimeout(() => {
                    resolve(connectToRemoteDesktop(vncFrame, statusCallback));
                }, 5000);
            });
        });
}

// Setup Remote Desktop frame event handlers
function setupRemoteDesktopFrameHandlers(vncFrame, statusCallback) {
    vncFrame.addEventListener('load', function() {
        if (vncFrame.src !== 'about:blank') {
            console.log('Remote Desktop frame loaded successfully');
            if (statusCallback) {
                statusCallback('Connected to Session', 'success');
            }
        }
    });
    
    vncFrame.addEventListener('error', function(e) {
        console.error('Error loading Remote Desktop frame:', e);
        if (statusCallback) {
            statusCallback('Error connecting to Remote Desktop. Retrying...', 'error');
        }
        // Try to reconnect after a delay
        setTimeout(() => connectToRemoteDesktop(vncFrame, statusCallback), 5000);
    });
}

export {
    connectToRemoteDesktop,
    setupRemoteDesktopFrameHandlers
}; 