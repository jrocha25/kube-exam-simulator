#!/bin/bash
exec >> /proc/1/fd/1 2>&1

# cleanup-exam-env.sh
# 
# This script cleans up the exam environment on the jumphost.
# It removes all resources created during the exam to prepare for a new exam.
#
# Usage: cleanup-exam-env.sh
#
# Example: cleanup-exam-env.sh

# Log function with timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Invoked over SSH, and sshd does not hand the image's ENV to the session, so
# CLUSTER_NAME arrives empty. env-setup and env-cleanup both fall back to
# "cluster", so name it explicitly rather than relying on two defaults agreeing.
CLUSTER_NAME=${CLUSTER_NAME:-cluster}

log "Starting exam environment cleanup"
log "Cleaning up cluster $CLUSTER_NAME"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null candidate@k8s-api-server "env-cleanup $CLUSTER_NAME"

#cleanup docker env
log "Cleaning up docker environment"
docker system prune -a --volumes -fa
docker network prune -fa
docker image prune -fa

# Remove the exam environment directory
log "Removing exam environment directory"
rm -rf /tmp/exam-env
rm -rf /tmp/exam

# Remove the exam assets directory
log "Removing exam assets directory"
rm -rf /tmp/exam-assets

log "Exam environment cleanup completed successfully"
exit 0 