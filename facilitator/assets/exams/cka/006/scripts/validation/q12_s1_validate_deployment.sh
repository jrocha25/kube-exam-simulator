#!/bin/bash
set -e

NAMESPACE="kustom-prod"
DEPLOYMENT="prod-trade-app"
EXPECTED_REPLICAS=3

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(echo "$JSON" | jq -r '.spec.replicas')
if [[ "$SPEC" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' declares $SPEC replicas, expected $EXPECTED_REPLICAS"
    exit 1
fi

READY=$(echo "$JSON" | jq -r '.status.readyReplicas // 0')
if [[ "$READY" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' has $READY/$EXPECTED_REPLICAS ready replicas"
    exit 1
fi

echo "✅ '$DEPLOYMENT' runs $EXPECTED_REPLICAS ready replicas in '$NAMESPACE'"
exit 0
