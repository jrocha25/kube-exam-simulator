#!/bin/bash
set -e

NAMESPACE="ops-charts"
DEPLOYMENT="beacon"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

DESIRED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$DESIRED" != "2" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' declares ${DESIRED:-0} replicas, expected 2"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    [[ "$READY" == "2" ]] && break
    sleep 5
done
if [[ "$READY" != "2" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has ${READY:-0} ready replicas, expected 2"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' has 2 ready replicas"
exit 0
