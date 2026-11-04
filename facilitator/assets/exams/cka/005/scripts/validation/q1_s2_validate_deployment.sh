#!/bin/bash
set -e

NAMESPACE="store-data"
DEPLOYMENT="ledger-api"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

DESIRED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')

if [[ "$DESIRED" != "1" ]]; then
    echo "❌ '$DEPLOYMENT' declares '$DESIRED' replicas, expected '1'"
    exit 1
fi

if [[ "${READY:-0}" != "1" ]]; then
    echo "❌ '$DEPLOYMENT' has ${READY:-0} ready replicas, expected 1"
    exit 1
fi

IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="api")].image}')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ Container 'api' runs '$IMAGE', expected 'nginx:1.27.4'"
    exit 1
fi

echo "✅ '$DEPLOYMENT' has 1 ready replica running nginx:1.27.4"
exit 0
