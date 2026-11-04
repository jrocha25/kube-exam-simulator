#!/bin/bash
set -e

NAMESPACE="ts-image"
DEPLOYMENT="billing-api"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
if [[ "$READY" != "3" ]]; then
    echo "❌ Expected 3 ready replicas, got '$READY'"
    exit 1
fi

echo "✅ All 3 replicas of '$DEPLOYMENT' are ready"
exit 0
