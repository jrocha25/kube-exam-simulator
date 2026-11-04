#!/bin/bash
set -e

NAMESPACE="cache-tier"
SERVICE="cache-svc"

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

PORT=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')
if [[ "$PORT" != "6379" ]]; then
    echo "❌ Incorrect service port. Expected '6379', got '$PORT'"
    exit 1
fi

TARGET_PORT=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].targetPort}')
if [[ "$TARGET_PORT" != "6379" ]]; then
    echo "❌ Incorrect target port. Expected '6379', got '$TARGET_PORT'"
    exit 1
fi

PROTOCOL=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].protocol}')
if [[ "$PROTOCOL" != "TCP" ]]; then
    echo "❌ Incorrect protocol. Expected 'TCP', got '$PROTOCOL'"
    exit 1
fi

SELECTOR=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.selector.app}')
if [[ "$SELECTOR" != "cache" ]]; then
    echo "❌ Incorrect selector. Expected 'app=cache', got 'app=$SELECTOR'"
    exit 1
fi

echo "✅ Service '$SERVICE' has the required ports, protocol and selector"
exit 0
