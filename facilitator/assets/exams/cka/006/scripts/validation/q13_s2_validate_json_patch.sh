#!/bin/bash
set -e

NAMESPACE="kustom-stage"
DEPLOYMENT="api"
OVERLAY="/tmp/exam/q13/overlays/staging"
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

# A JSON 6902 patch is identifiable by its op/path form; a strategic merge patch
# setting replicas would satisfy the replica count but not the question.
if ! grep -rqsE '"?op"?:[[:space:]]*"?(replace|add)"?' "$OVERLAY"; then
    echo "❌ No JSON 6902 patch (an 'op:' entry) was found under '$OVERLAY'"
    exit 1
fi
if ! grep -rqs '/spec/replicas' "$OVERLAY"; then
    echo "❌ No patch under '$OVERLAY' targets the path '/spec/replicas'"
    exit 1
fi

echo "✅ A JSON 6902 patch set the replica count to $EXPECTED_REPLICAS"
exit 0
