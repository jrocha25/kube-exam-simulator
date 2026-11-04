/**
 * Exam API Service
 * Handles all API interactions for the exam functionality
 */

// Function to get exam ID from URL
function getExamId() {
    // Extract exam ID from URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    const examId = urlParams.get('id');
    
    if (!examId) {
        console.error('No exam ID found in URL');
        alert('Error: No exam ID provided. Please return to the dashboard.');
        // redirect to dashboard
        window.location.href = '/';
    }
    
    return examId;
}

// Function to check exam status
function checkExamStatus(examId) {
    return fetch(`/facilitator/api/v1/exams/${examId}/status`)
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            return data.status || null;
        });
}

// Function to fetch exam data
function fetchExamData(examId) {
    const apiUrl = `/facilitator/api/v1/exams/${examId}/questions`;
    
    return fetch(apiUrl)
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            return data;
        })
        .catch(error => {
            console.error('Error loading exam questions:', error);
            throw error; // Re-throw to be handled by the calling function
        });
}

// Function to fetch current exam information
function fetchCurrentExamInfo() {
    return fetch('/facilitator/api/v1/exams/current')
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            return data;
        });
}

// Function to evaluate exam
function evaluateExam(examId) {
    return fetch(`/facilitator/api/v1/exams/${examId}/evaluate`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        }
    })
    .then(response => {
        if (!response.ok) {
            throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
    });
}

// Function to terminate session
function terminateSession(examId) {
    return fetch(`/facilitator/api/v1/exams/${examId}/terminate`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        }
    })
    .then(response => {
        if (!response.ok) {
            throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
    });
}

// Function to get VNC info
function getVncInfo() {
    return fetch('/api/vnc-info')
        .then(response => response.json())
        .catch(error => {
            console.error('Error fetching VNC info:', error);
            throw error;
        });
}

// Function to persist exam events (start/end time) used to restore the exam timer
function saveExamEvent(examId, events) {
    return fetch(`/facilitator/api/v1/exams/${examId}/events`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ events })
    })
    .then(response => {
        if (!response.ok) {
            throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
    })
    .catch(error => {
        console.error('Error saving exam event:', error);
        // Don't throw error to avoid disrupting exam flow
        // But still log it for debugging
    });
}

// Export the API functions
export {
    getExamId,
    checkExamStatus,
    fetchExamData,
    fetchCurrentExamInfo,
    evaluateExam,
    terminateSession,
    getVncInfo,
    saveExamEvent
}; 