#!/bin/bash
set -e

NAMESPACE="svc-edge"
SERVICE="edge-public"

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

TYPE=$(echo "$JSON" | jq -r '.spec.type')
if [[ "$TYPE" != "NodePort" ]]; then
    echo "❌ '$SERVICE' is of type '$TYPE', expected 'NodePort'"
    exit 1
fi

PORT=$(echo "$JSON" | jq -r '.spec.ports[0].port')
NODEPORT=$(echo "$JSON" | jq -r '.spec.ports[0].nodePort')
TARGET=$(echo "$JSON" | jq -r '.spec.ports[0].targetPort')

if [[ "$PORT" != "80" ]]; then
    echo "❌ '$SERVICE' serves on port $PORT, expected 80"
    exit 1
fi
if [[ "$NODEPORT" != "30880" ]]; then
    echo "❌ '$SERVICE' uses node port $NODEPORT, expected 30880"
    exit 1
fi
if [[ "$TARGET" != "http-web" ]]; then
    echo "❌ '$SERVICE' targets '$TARGET', expected the named container port 'http-web'"
    exit 1
fi

echo "✅ '$SERVICE' is a NodePort Service on 30880 targeting the named port"
exit 0
