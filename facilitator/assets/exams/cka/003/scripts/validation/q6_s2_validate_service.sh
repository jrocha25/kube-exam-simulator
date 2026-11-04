#!/bin/bash
set -e

NAMESPACE="web-shop"
SERVICE="shop-web-svc"

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

TYPE=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.type}')
if [[ "$TYPE" != "ClusterIP" ]]; then
    echo "❌ Incorrect service type. Expected 'ClusterIP', got '$TYPE'"
    exit 1
fi

PORT=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')
if [[ "$PORT" != "80" ]]; then
    echo "❌ Incorrect service port. Expected '80', got '$PORT'"
    exit 1
fi

TARGET_PORT=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].targetPort}')
if [[ "$TARGET_PORT" != "80" ]]; then
    echo "❌ Incorrect target port. Expected '80', got '$TARGET_PORT'"
    exit 1
fi

PROTOCOL=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].protocol}')
if [[ "$PROTOCOL" != "TCP" ]]; then
    echo "❌ Incorrect protocol. Expected 'TCP', got '$PROTOCOL'"
    exit 1
fi

SELECTOR=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.selector.app}')
if [[ "$SELECTOR" != "shop-web" ]]; then
    echo "❌ Incorrect selector. Expected 'app=shop-web', got 'app=$SELECTOR'"
    exit 1
fi

ENDPOINT_COUNT=$(kubectl get endpointslice -n "$NAMESPACE" -l kubernetes.io/service-name="$SERVICE" -o json | jq '[.items[].endpoints // [] | .[] | select(.conditions.ready == true)] | length')
if [[ "$ENDPOINT_COUNT" != "2" ]]; then
    echo "❌ Service '$SERVICE' has $ENDPOINT_COUNT ready endpoint(s), expected 2"
    exit 1
fi

echo "✅ Service '$SERVICE' is configured correctly and has 2 ready endpoints"
exit 0
