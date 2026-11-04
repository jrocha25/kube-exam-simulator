#!/bin/bash
set -e

NAMESPACE="rbac-excess"
SA="backup-agent"

if ! kubectl get serviceaccount "$SA" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ ServiceAccount '$SA' no longer exists in namespace '$NAMESPACE'; the account had to be kept"
    exit 1
fi

echo "✅ ServiceAccount '$SA' still exists in '$NAMESPACE'"
exit 0
