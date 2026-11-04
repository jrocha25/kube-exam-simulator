#!/bin/bash

set -e

# Readiness, not placement. A preference is a scoring hint: the scheduler is free
# to ignore it under pressure, so asserting which node won would be grading the
# scheduler rather than the answer.

NAMESPACE="sched-prefer"
DEPLOYMENT="tracking-api"
REPLICAS="3"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

DECLARED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$DECLARED" != "$REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' declares ${DECLARED:-no} replicas, expected $REPLICAS"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
    [[ "$READY" == "$REPLICAS" ]] && break
    sleep 5
done

if [[ "$READY" != "$REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' has ${READY:-0}/${REPLICAS} ready replicas"
    exit 1
fi

echo "✅ All $REPLICAS replicas of '$DEPLOYMENT' are ready"
exit 0
