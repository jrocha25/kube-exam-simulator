#!/bin/bash
set -e

NAMESPACE="ts-service"
SERVICE="catalog-svc"

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SELECTOR=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.selector.app}')
if [[ "$SELECTOR" != "catalog" ]]; then
    echo "❌ Incorrect selector. Expected 'app=catalog', got 'app=$SELECTOR'"
    exit 1
fi

SELECTOR_SIZE=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json | jq '.spec.selector // {} | length')
if [[ "$SELECTOR_SIZE" != "1" ]]; then
    echo "❌ Service '$SERVICE' must select Pods by the single label app=catalog (found $SELECTOR_SIZE selector labels)"
    exit 1
fi

echo "✅ Service '$SERVICE' selects Pods with the label app=catalog"
exit 0
