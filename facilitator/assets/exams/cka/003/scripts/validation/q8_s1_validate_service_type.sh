#!/bin/bash
set -e

NAMESPACE="cache-tier"
SERVICE="cache-svc"

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

TYPE=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.type}')
if [[ "$TYPE" != "NodePort" ]]; then
    echo "❌ Incorrect service type. Expected 'NodePort', got '$TYPE'"
    exit 1
fi

NODE_PORT=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')
if [[ "$NODE_PORT" != "31379" ]]; then
    echo "❌ Incorrect node port. Expected '31379', got '$NODE_PORT'"
    exit 1
fi

echo "✅ Service '$SERVICE' is a NodePort service on node port 31379"
exit 0
