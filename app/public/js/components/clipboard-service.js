/**
 * Clipboard Service
 * Handles clipboard-related functionality
 */

/**
 * Copy text to remote desktop clipboard via facilitator API
 * @param {string} content - Text content to copy
 * @private
 */
async function copyToRemoteClipboard(content) {
    try {
        // Fire and forget API call
        fetch('/facilitator/api/v1/remote-desktop/clipboard', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ content })
        });
    } catch (error) {
        console.error('Failed to copy to remote clipboard:', error);
        // Don't throw error as this is a non-critical operation
    }
}

/**
 * Setup click-to-copy functionality for inline code elements
 * Uses event delegation to handle all inline-code elements
 */
function setupInlineCodeCopy() {
    document.addEventListener('click', function(event) {
        if (event.target && event.target.matches('.inline-code')) {
            const codeText = event.target.textContent;

            // Copy to remote desktop clipboard
            copyToRemoteClipboard(codeText);
            
            // Copy to local clipboard
            navigator.clipboard.writeText(codeText).catch(err => {
                console.error('Could not copy text to clipboard:', err);
            });

        }
    });
}

export {
    setupInlineCodeCopy
}; 