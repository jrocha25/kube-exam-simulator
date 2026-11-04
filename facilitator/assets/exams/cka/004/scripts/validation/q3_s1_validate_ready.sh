#!/bin/bash
set -e

NAMESPACE="analytics"
DEPLOYMENT="report-builder"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "3" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep 3 replicas (got: '$REPLICAS')"
    exit 1
fi

READY=""
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [[ "$READY" == "3" ]]; then
        break
    fi
    sleep 5
done

if [[ "$READY" != "3" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' does not have 3 ready replicas (ready: '${READY:-0}')"
    exit 1
fi

echo "✅ All 3 replicas of '$DEPLOYMENT' are ready"
exit 0
