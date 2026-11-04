#!/bin/bash
set -e

NAMESPACE="spread-lab"
DEPLOYMENT="spread-web"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
if [[ "$READY" != "4" ]]; then
    echo "❌ Expected 4 ready replicas, got '$READY'"
    exit 1
fi

echo "✅ All 4 replicas of '$DEPLOYMENT' are ready"
exit 0
