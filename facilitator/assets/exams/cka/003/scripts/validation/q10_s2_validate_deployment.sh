#!/bin/bash
set -e

NAMESPACE="helm-apps"
DEPLOYMENT="webstack-web"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "3" ]]; then
    echo "❌ Incorrect replica count. Expected '3', got '$REPLICAS'"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
if [[ "$READY" != "3" ]]; then
    echo "❌ Expected 3 ready replicas, got '$READY'"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' has 3 ready replicas"
exit 0
