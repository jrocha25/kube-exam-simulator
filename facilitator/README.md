# Facilitator Service

A Node.js service that provides SSH jumphost functionality and exam management capabilities via a REST API.

## Features

- Execute commands on a remote SSH jumphost
- Support for both password and passwordless SSH authentication
- Exam management API endpoints (some implemented, others are placeholders)
- Secure and modular architecture
- Comprehensive logging
- Containerization with Docker
- Integration with Docker Compose for multi-service deployment

## Prerequisites

- Node.js 18+
- npm or yarn
- SSH access to the target jumphost

## Installation

### Local Development

1. Clone the repository
2. Navigate to the project directory
3. Install dependencies:

```bash
npm install
```

4. Create a `.env` file based on the provided example:

```
PORT=3000
NODE_ENV=development

# SSH Jumphost Configuration
SSH_HOST=<your-ssh-host>
SSH_PORT=22
SSH_USERNAME=<your-ssh-username>
SSH_PASSWORD=<your-ssh-password>
# Alternatively, use SSH key authentication
# SSH_PRIVATE_KEY_PATH=/path/to/private/key

# Logging Configuration
LOG_LEVEL=info
```

5. Start the development server:

```bash
npm run dev
```

### Docker Deployment

#### Standalone

1. Build the Docker image:

```bash
docker build -t facilitator-service .
```

2. Run the container:

```bash
docker run -p 3001:3000 --env-file .env facilitator-service
```

#### Docker Compose

The facilitator service is integrated into the main Docker Compose configuration at the project root. To run it with the full stack:

```bash
cd ..
docker compose up -d
```

This will start the facilitator service along with all other services, including the jumphost that the facilitator connects to for SSH command execution. In Docker Compose, the service is configured to use passwordless SSH authentication with the jumphost.

The service is accessible at:
- URL: http://localhost:3001
- Internal network name: facilitator

## API Endpoints

### SSH Command Execution

- **POST /api/v1/execute**
  - Execute a command on the SSH jumphost
  - Request body: `{ "command": "your-command-here" }`
  - Response: `{ "exitCode": 0, "stdout": "output", "stderr": "errors" }`

### Exam Management

- **GET /api/v1/exams/**
  - Get a list of all exams
  - Returns an array of exam objects containing id, name, category, description, etc.

- **POST /api/v1/exams/**
  - Create a new exam
  - Returns exam ID and type (placeholder)

- **GET /api/v1/exams/:examId/assets**
  - Get assets for a specific exam
  - Returns empty object (placeholder)

- **GET /api/v1/exams/:examId/questions/**
  - Get questions for a specific exam
  - Returns empty object (placeholder)

- **POST /api/v1/exams/:examId/evaluate/**
  - Evaluate an exam
  - Returns empty object (placeholder)

- **POST /api/v1/exams/:examId/end**
  - End an exam
  - Returns empty object (placeholder)

## License

ISC 