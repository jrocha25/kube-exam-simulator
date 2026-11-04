#!/bin/bash
set -e

NAMESPACE="rbac-app"
SA="report-runner"

if ! kubectl get serviceaccount "$SA" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ ServiceAccount '$SA' not found in namespace '$NAMESPACE'"
    exit 1
fi

echo "✅ ServiceAccount '$SA' exists in '$NAMESPACE'"
exit 0
