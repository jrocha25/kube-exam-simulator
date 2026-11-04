#!/bin/bash
set -e

NAMESPACE="delivery"
SA_NAME="pipeline-bot"

if ! kubectl get serviceaccount "$SA_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ ServiceAccount '$SA_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

echo "✅ ServiceAccount '$SA_NAME' exists in namespace '$NAMESPACE'"
exit 0
