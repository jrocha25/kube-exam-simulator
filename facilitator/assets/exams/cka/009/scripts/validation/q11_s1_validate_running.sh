#!/bin/bash

set -e

# The bulk of the marks: the workload actually schedules again.

NAMESPACE="ts-sched"
DEPLOYMENT="customs-broker"
REPLICAS="3"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
    [[ "$READY" == "$REPLICAS" ]] && break
    sleep 5
done

if [[ "$READY" != "$REPLICAS" ]]; then
    PENDING=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
        --field-selector=status.phase=Pending -o name 2> /dev/null | wc -l)
    echo "❌ '$DEPLOYMENT' has ${READY:-0}/${REPLICAS} ready replicas (${PENDING} still Pending)"
    exit 1
fi

echo "✅ All $REPLICAS replicas of '$DEPLOYMENT' are running and ready"
exit 0
