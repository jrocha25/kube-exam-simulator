#!/bin/bash

set -e

# The base declares 1 replica and is off limits, so 3 can only have come from the
# overlay. Mechanism is free -- a patch or the replicas transformer both count.

NAMESPACE="kustom-sched"
DEPLOYMENT="freight-api"
REPLICAS="3"

DECLARED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2> /dev/null || true)
if [[ "$DECLARED" != "$REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' declares ${DECLARED:-no} replicas, expected $REPLICAS"
    exit 1
fi

echo "✅ '$DEPLOYMENT' declares $REPLICAS replicas, set from the overlay"
exit 0
