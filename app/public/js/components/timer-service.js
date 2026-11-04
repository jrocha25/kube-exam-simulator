/**
 * Timer Service
 * Handles timer functionality for the exam
 */

let timerDuration = 120; // Default timer duration in minutes
let timerInterval = null;
let timerElement = null;
let onTimerEndCallback = null;
let isTimerRunning = false;
const timeThresholds = [30, 10, 0]; // Time thresholds in minutes
let timeThresholdCallbacks = {}; // Callbacks for time thresholds
let processedThresholds = new Set(); // Track which thresholds have been processed

/**
 * Set timer duration
 * @param {number} duration - Duration in minutes
 */
function setTimerDuration(duration) {
    timerDuration = duration;
    // Reset processed thresholds when timer duration changes
    processedThresholds.clear();
}

/**
 * Register callbacks for specific time thresholds
 * @param {Object} callbacks - Object with threshold minutes as keys and callback functions as values
 */
function registerTimeThresholdCallbacks(callbacks) {
    timeThresholdCallbacks = { ...timeThresholdCallbacks, ...callbacks };
}

/**
 * Get remaining time
 * @returns {number} Remaining time in minutes
 */
function getRemainingTime() {
    return timerDuration;
}

/**
 * Calculate remaining exam time based on exam info
 * @param {Object} examInfo - The exam information object
 * @returns {number} Remaining time in minutes
 */
function calculateRemainingTime(examInfo) {
    // If exam hasn't started yet or no duration set, return default
    if (!examInfo.info?.examDurationInMinutes) {
        return getRemainingTime();
    }
    
    // Check if exam has ended
    if (examInfo.info?.events?.examEndTime) {
        return 0; // No time remaining if exam is finished
    }
    
    // If exam has started, calculate remaining time
    if (examInfo.info?.events?.examStartTime) {
        // Make sure we have a proper number value for startTime
        let startTime = examInfo.info.events.examStartTime;
        
        // Parse the timestamp to ensure it's a number (could be stored as string)
        if (typeof startTime === 'string') {
            startTime = parseInt(startTime, 10);
        }
        
        // Debug log to identify the issue
        console.log('Start time (epoch):', startTime);
        console.log('Current time (epoch):', Date.now());
        console.log('Exam duration (minutes):', examInfo.info.examDurationInMinutes);
        
        const durationMs = examInfo.info.examDurationInMinutes * 60 * 1000;
        const elapsedMs = Date.now() - startTime;
        const remainingMs = Math.max(0, durationMs - elapsedMs);
        
        // Debug log for troubleshooting
        console.log('Duration (ms):', durationMs);
        console.log('Elapsed (ms):', elapsedMs);
        console.log('Remaining (ms):', remainingMs);
        console.log('Remaining (minutes):', Math.ceil(remainingMs / (60 * 1000)));
        
        // Convert ms to minutes
        return Math.ceil(remainingMs / (60 * 1000));
    }
    
    // Default: return full duration if exam hasn't started
    return examInfo.info.examDurationInMinutes;
}

/**
 * Initialize the timer
 * @param {HTMLElement} element - DOM element to display the timer
 * @param {number} minutes - Timer duration in minutes
 * @param {Object} options - Optional configuration
 * @param {Function} options.onTimerEnd - Callback function when timer ends
 */
function initTimer(element, minutes, options = {}) {
    timerElement = element;
    timerDuration = minutes;
    onTimerEndCallback = options.onTimerEnd;
    
    // Reset processed thresholds when initializing new timer
    processedThresholds.clear();
    
    updateTimerDisplay(minutes);
}

/**
 * Check if a time threshold has been reached and trigger callback
 * @param {number} remainingMinutes - Remaining time in minutes
 * @param {number} remainingSeconds - Remaining time in seconds
 */
function checkTimeThresholds(remainingMinutes, remainingSeconds) {
    // Check each threshold
    timeThresholds.forEach(threshold => {
        // If we just crossed this threshold and haven't processed it yet
        if (remainingMinutes === threshold && 
            remainingSeconds === 0 && 
            !processedThresholds.has(threshold)) {
            
            // Mark as processed
            processedThresholds.add(threshold);
            
            // Call the registered callback if exists
            if (timeThresholdCallbacks[threshold]) {
                timeThresholdCallbacks[threshold](threshold);
            }
        }
    });
}

/**
 * Start the timer
 */
function startTimer() {
    if (isTimerRunning) return;
    isTimerRunning = true;
    
    let remainingSeconds = timerDuration * 60;
    
    timerInterval = setInterval(() => {
        remainingSeconds--;
        
        if (remainingSeconds <= 0) {
            stopTimer();
            updateTimerDisplay(0);
            
            if (onTimerEndCallback) {
                onTimerEndCallback();
            }
            return;
        }
        
        const minutes = Math.floor(remainingSeconds / 60);
        const seconds = remainingSeconds % 60;
        
        // Check if we've hit any time thresholds
        checkTimeThresholds(minutes, seconds);
        
        updateTimerDisplay(minutes, seconds);
    }, 1000);
}

/**
 * Stop the timer
 */
function stopTimer() {
    if (timerInterval) {
        clearInterval(timerInterval);
        timerInterval = null;
        isTimerRunning = false;
    }
}

/**
 * Reset the timer
 */
function resetTimer() {
    stopTimer();
    timerDuration = 120; // Reset to default
    processedThresholds.clear();
    if (timerElement) {
        updateTimerDisplay(timerDuration);
    }
}

/**
 * Update the timer display
 * @param {number} minutes - Minutes remaining
 * @param {number} seconds - Seconds remaining
 */
function updateTimerDisplay(minutes, seconds = 0) {
    if (!timerElement) return;
    
    const formattedMinutes = String(minutes).padStart(2, '0');
    const formattedSeconds = String(seconds).padStart(2, '0');
    
    timerElement.textContent = `${formattedMinutes}:${formattedSeconds}`;
    
    // Add visual warning when less than 5 minutes remaining
    if (minutes < 5) {
        timerElement.classList.add('timer-warning');
    } else {
        timerElement.classList.remove('timer-warning');
    }
}

// Export the timer service
export {
    setTimerDuration,
    getRemainingTime,
    calculateRemainingTime,
    initTimer,
    startTimer,
    stopTimer,
    resetTimer,
    registerTimeThresholdCallbacks
}; 