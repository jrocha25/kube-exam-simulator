#!/bin/bash
set -e

NAMESPACE="svc-orders"
SERVICE="checkout"
DEPLOYMENT="checkout"

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

TYPE=$(echo "$JSON" | jq -r '.spec.type')
if [[ "$TYPE" != "ClusterIP" ]]; then
    echo "❌ Service '$SERVICE' is of type '$TYPE', expected 'ClusterIP'"
    exit 1
fi

PORT=$(echo "$JSON" | jq -r '.spec.ports[0].port')
if [[ "$PORT" != "80" ]]; then
    echo "❌ Service '$SERVICE' serves on port $PORT, expected 80"
    exit 1
fi

# The Deployment and its pod labels were declared off limits, so an "endpoints
# appeared" result that came from relabelling the pods is not a pass.
LABELS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null || true)
if [[ "$LABELS" != "checkout-api" ]]; then
    echo "❌ The Deployment's pod label is now 'app=${LABELS:-<none>}'."
    echo "   The Deployment and its Pods were not to be changed."
    exit 1
fi

echo "✅ Service '$SERVICE' kept its required shape and the Deployment is untouched"
exit 0
