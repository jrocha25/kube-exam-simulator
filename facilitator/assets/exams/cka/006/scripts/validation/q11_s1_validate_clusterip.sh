#!/bin/bash
set -e

NAMESPACE="svc-edge"
SERVICE="edge-internal"
PORT_NAME="http-web"

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

TYPE=$(echo "$JSON" | jq -r '.spec.type')
if [[ "$TYPE" != "ClusterIP" ]]; then
    echo "❌ '$SERVICE' is of type '$TYPE', expected 'ClusterIP'"
    exit 1
fi

PORT=$(echo "$JSON" | jq -r '.spec.ports[0].port')
if [[ "$PORT" != "8080" ]]; then
    echo "❌ '$SERVICE' serves on port $PORT, expected 8080"
    exit 1
fi

TARGET=$(echo "$JSON" | jq -r '.spec.ports[0].targetPort')
if [[ "$TARGET" != "$PORT_NAME" ]]; then
    echo "❌ '$SERVICE' targets '$TARGET', expected the container port by name ('$PORT_NAME')"
    exit 1
fi

READY=$(kubectl get endpointslice -n "$NAMESPACE" -l "kubernetes.io/service-name=$SERVICE" \
    -o json 2>/dev/null | jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length')
if [[ "${READY:-0}" -lt 1 ]]; then
    echo "❌ '$SERVICE' has no ready endpoints -- it does not select the edge-web Pods"
    exit 1
fi

echo "✅ '$SERVICE' serves on 8080 and targets the named container port"
exit 0
