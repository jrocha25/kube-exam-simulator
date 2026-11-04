/**
 * Static files utility
 * Handles the setup of necessary directories and files
 */

const fs = require('fs');
const path = require('path');

/**
 * Sets up the necessary static file structure
 * Creates public directory if it doesn't exist
 * Copies index.html to public directory if needed
 */
function setupStaticFiles() {
    // Create the public directory if it doesn't exist
    const publicDir = path.join(__dirname, '..', 'public');
    if (!fs.existsSync(publicDir)) {
        fs.mkdirSync(publicDir, { recursive: true });
        console.log('Created public directory');
    }

    // Copy index.html to public directory if it doesn't exist
    const indexHtmlSrc = path.join(__dirname, '..', 'index.html');
    const indexHtmlDest = path.join(publicDir, 'index.html');
    if (fs.existsSync(indexHtmlSrc) && !fs.existsSync(indexHtmlDest)) {
        fs.copyFileSync(indexHtmlSrc, indexHtmlDest);
        console.log('Copied index.html to public directory');
    }
}

module.exports = setupStaticFiles; 