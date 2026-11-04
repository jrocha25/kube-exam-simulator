#!/bin/bash

set -e

# The suffixed names are the evidence that nameSuffix was applied: if the overlay
# omitted it the objects land as "parcel-index" and are not found here at all.

NAMESPACE="kustom-intro"
DEPLOYMENT="parcel-index-dev"
SERVICE="parcel-index-dev"
REPLICAS="2"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
    [[ "$READY" == "$REPLICAS" ]] && break
    sleep 5
done

if [[ "$READY" != "$REPLICAS" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has ${READY:-0}/${REPLICAS} ready replicas"
    exit 1
fi

echo "✅ '$DEPLOYMENT' and Service '$SERVICE' exist in '$NAMESPACE' with $REPLICAS ready replicas"
exit 0
