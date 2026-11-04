#!/bin/bash
set -e

NAMESPACE="cache-tier"
SERVICE="cache-svc"

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SLICE_JSON=$(kubectl get endpointslice -n "$NAMESPACE" -l kubernetes.io/service-name="$SERVICE" -o json)

ENDPOINT_COUNT=$(echo "$SLICE_JSON" | jq '[.items[].endpoints // [] | .[] | select(.conditions.ready == true)] | length')
if [[ "$ENDPOINT_COUNT" != "2" ]]; then
    echo "❌ Service '$SERVICE' has $ENDPOINT_COUNT ready endpoint(s), expected 2"
    exit 1
fi

PORT_MATCH=$(echo "$SLICE_JSON" | jq '[.items[].ports // [] | .[] | select(.port == 6379)] | length')
if [[ "$PORT_MATCH" == "0" ]]; then
    echo "❌ Service '$SERVICE' does not expose endpoints on port 6379"
    exit 1
fi

echo "✅ Service '$SERVICE' has 2 ready endpoints on port 6379"
exit 0
