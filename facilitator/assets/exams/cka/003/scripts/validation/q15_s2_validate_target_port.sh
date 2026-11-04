#!/bin/bash
set -e

NAMESPACE="ts-service"
SERVICE="catalog-svc"

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

TYPE=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.type}')
if [[ "$TYPE" != "ClusterIP" ]]; then
    echo "❌ Service '$SERVICE' must stay a ClusterIP service (got: '$TYPE')"
    exit 1
fi

PORT=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')
if [[ "$PORT" != "80" ]]; then
    echo "❌ Service '$SERVICE' must stay on port 80 (got: '$PORT')"
    exit 1
fi

TARGET_PORT=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].targetPort}')
if [[ "$TARGET_PORT" != "80" ]]; then
    echo "❌ Incorrect target port. Expected '80', got '$TARGET_PORT'"
    exit 1
fi

echo "✅ Service '$SERVICE' is a ClusterIP service on port 80 forwarding to target port 80"
exit 0
