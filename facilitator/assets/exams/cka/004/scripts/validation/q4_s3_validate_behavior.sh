#!/bin/bash
set -e

NAMESPACE="checkout"
HPA_NAME="checkout-hpa"

if ! kubectl get horizontalpodautoscaler "$HPA_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HorizontalPodAutoscaler '$HPA_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

WINDOW=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA_NAME" -n "$NAMESPACE" -o json \
    | jq -r '.spec.behavior.scaleDown.stabilizationWindowSeconds // empty')

if [[ "$WINDOW" != "45" ]]; then
    echo "❌ Incorrect scale down stabilization window. Expected '45', got '${WINDOW:-<none>}'"
    exit 1
fi

echo "✅ '$HPA_NAME' stabilizes scale down over 45 seconds"
exit 0
