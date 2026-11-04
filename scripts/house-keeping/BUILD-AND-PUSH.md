# CK-X Simulator Scripts

This directory contains utility scripts for the CK-X Simulator project.

## Build and Push Script

The `build-and-push.sh` script automates the process of building and pushing all Docker images defined in the compose.yaml file to Docker Hub.

The images `docker-compose.yaml` names are built and pushed to GHCR non-interactively by `.github/workflows/images.yml`; this script remains the way to publish to Docker Hub by hand.

### Prerequisites

- Docker installed and running
- Docker Hub account
- Logged in to Docker Hub via `docker login`

### Usage

1. Ensure you are logged in to Docker Hub:
   ```
   docker login
   ```

2. (Optional) Set your Docker Hub username if different from the default:
   ```
   export DOCKER_HUB_USERNAME=yourusername
   ```

3. Run the script from the `script` directory:
   ```
   cd script
   ./build-and-push.sh
   ```
   Or run it from anywhere by providing the full path:
   ```
   /path/to/killer-clone/script/build-and-push.sh
   ```

4. When prompted, enter a tag for the images:
   - Press Enter to use the default tag "latest"
   - Or enter a custom tag (e.g., "v1.0.0", "dev", "staging")

### Dealing with Docker Login Issues

If you encounter problems with the Docker login check:

1. The script now uses multiple methods to verify login status, which should be more reliable
2. If you're sure you're logged in but the script doesn't detect it, you can choose to continue anyway when prompted
3. You can completely skip the login check by setting an environment variable:
   ```
   export SKIP_LOGIN_CHECK=true
   ./build-and-push.sh
   ```

### What the Script Does

1. Checks if you're logged in to Docker Hub (with improved reliability)
2. Determines the correct paths to all project directories
3. Prompts for a tag name for the images
4. Lists all images that will be built and pushed with the specified tag
5. Asks for confirmation before proceeding
6. Builds and pushes each image in sequence:
   - ck-x-simulator-remote-desktop
   - ck-x-simulator-webapp
   - ck-x-simulator-nginx
   - ck-x-simulator-jumphost
   - ck-x-simulator-remote-terminal
   - ck-x-simulator-cluster
   - ck-x-simulator-facilitator

### Examples

Build with the default "latest" tag:
```
cd script
./build-and-push.sh
# Press Enter when prompted for tag
```

Build with a version tag:
```
cd script
./build-and-push.sh
# Enter "v1.2.3" when prompted for tag
```

Build with environment-specific tag:
```
cd script
./build-and-push.sh
# Enter "staging" or "production" when prompted for tag
```

Skip the Docker login check:
```
cd script
SKIP_LOGIN_CHECK=true ./build-and-push.sh
```

### Troubleshooting

If you encounter any issues:

1. Make sure you are logged in to Docker Hub
2. If the login check fails but you're sure you're logged in, try the SKIP_LOGIN_CHECK option
3. Ensure all directories referenced in the script exist
4. Make sure you're running the script from the correct location (inside the `script` directory)
5. Check that you have the necessary permissions to build and push images
6. Verify your Docker Hub account has sufficient privileges 