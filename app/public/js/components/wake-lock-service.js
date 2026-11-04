/**
 * Wake Lock Service
 * Prevents device from sleeping during exam
 */

let wakeLock = null;

/**
 * Acquire screen wake lock to prevent device from sleeping
 * @returns {Promise<boolean>} True if wake lock acquired successfully
 */
async function acquireWakeLock() {
    // Check if Wake Lock API is supported
    if ('wakeLock' in navigator) {
        try {
            // Attempt to acquire wake lock
            wakeLock = await navigator.wakeLock.request('screen');
            
            console.log('Wake Lock activated');
            
            // Add release event listener for page visibility change
            document.addEventListener('visibilitychange', handleVisibilityChange);
            
            return true;
        } catch (err) {
            console.error('Failed to acquire Wake Lock:', err);
            return false;
        }
    } else {
        console.warn('Wake Lock API not supported in this browser');
        return false;
    }
}

/**
 * Handle visibility change to reacquire wake lock when page becomes visible again
 */
function handleVisibilityChange() {
    if (document.visibilityState === 'visible') {
        // Reacquire wake lock when tab becomes visible again
        acquireWakeLock();
    }
}

/**
 * Release wake lock manually
 */
async function releaseWakeLock() {
    if (wakeLock) {
        try {
            await wakeLock.release();
            wakeLock = null;
            console.log('Wake Lock released');
            
            // Remove event listener
            document.removeEventListener('visibilitychange', handleVisibilityChange);
            
            return true;
        } catch (err) {
            console.error('Failed to release Wake Lock:', err);
            return false;
        }
    }
    return true;
}

/**
 * Check if wake lock is currently active
 * @returns {boolean} True if wake lock is active
 */
function isWakeLockActive() {
    return wakeLock !== null;
}

// Export the wake lock functions
export {
    acquireWakeLock,
    releaseWakeLock,
    isWakeLockActive
}; 