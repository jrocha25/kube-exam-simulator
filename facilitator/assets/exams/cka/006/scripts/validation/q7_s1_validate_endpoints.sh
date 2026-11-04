#!/bin/bash
set -e

NAMESPACE="svc-orders"
SERVICE="checkout"
EXPECTED=2

READY=$(kubectl get endpointslice -n "$NAMESPACE" \
    -l "kubernetes.io/service-name=$SERVICE" -o json 2>/dev/null \
    | jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length')

if [[ "${READY:-0}" -lt "$EXPECTED" ]]; then
    echo "❌ Service '$SERVICE' has ${READY:-0} ready endpoints, expected $EXPECTED"
    exit 1
fi

echo "✅ Service '$SERVICE' has ${READY} ready endpoints"
exit 0
