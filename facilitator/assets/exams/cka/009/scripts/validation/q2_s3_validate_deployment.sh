#!/bin/bash

set -e

# The Deployment consumes the ConfigMap through envFrom, so it only reaches Ready
# once a ConfigMap by that exact name exists.

NAMESPACE="kustom-gen"
DEPLOYMENT="depot-config"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
    [[ "$READY" == "1" ]] && break
    sleep 5
done

if [[ "$READY" != "1" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has ${READY:-0}/1 ready replicas"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' is running and consuming the generated ConfigMap"
exit 0
