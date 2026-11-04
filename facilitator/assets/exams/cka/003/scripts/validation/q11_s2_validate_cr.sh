#!/bin/bash
set -e

NAMESPACE="crd-lab"
CR_NAME="nightly-db"

if ! kubectl get backupjobs.ops.example.com "$CR_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ BackupJob '$CR_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

SCHEDULE=$(kubectl get backupjobs.ops.example.com "$CR_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.schedule}')
if [[ "$SCHEDULE" != "0 2 * * *" ]]; then
    echo "❌ Incorrect spec.schedule. Expected '0 2 * * *', got '$SCHEDULE'"
    exit 1
fi

RETENTION=$(kubectl get backupjobs.ops.example.com "$CR_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.retention}')
if [[ "$RETENTION" != "7" ]]; then
    echo "❌ Incorrect spec.retention. Expected '7', got '$RETENTION'"
    exit 1
fi

echo "✅ BackupJob '$CR_NAME' exists with the required schedule and retention"
exit 0
