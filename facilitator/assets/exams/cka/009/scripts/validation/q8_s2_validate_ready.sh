#!/bin/bash

set -e

NAMESPACE="sched-antiaff"
DEPLOYMENT="label-printer"
REPLICAS="2"

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
