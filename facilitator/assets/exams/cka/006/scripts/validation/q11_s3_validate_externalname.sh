#!/bin/bash
set -e

NAMESPACE="svc-edge"
SERVICE="edge-vendor"
EXPECTED="vendor.example.com"

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

TYPE=$(echo "$JSON" | jq -r '.spec.type')
if [[ "$TYPE" != "ExternalName" ]]; then
    echo "❌ '$SERVICE' is of type '$TYPE', expected 'ExternalName'"
    exit 1
fi

NAME=$(echo "$JSON" | jq -r '.spec.externalName // empty')
if [[ "$NAME" != "$EXPECTED" ]]; then
    echo "❌ '$SERVICE' points at '${NAME:-<nothing>}', expected '$EXPECTED'"
    exit 1
fi

CLUSTER_IP=$(echo "$JSON" | jq -r '.spec.clusterIP // empty')
if [[ -n "$CLUSTER_IP" && "$CLUSTER_IP" != "None" ]]; then
    echo "❌ '$SERVICE' allocated the ClusterIP '$CLUSTER_IP'; an ExternalName Service must not have one"
    exit 1
fi

echo "✅ '$SERVICE' is an ExternalName Service pointing at '$EXPECTED'"
exit 0
