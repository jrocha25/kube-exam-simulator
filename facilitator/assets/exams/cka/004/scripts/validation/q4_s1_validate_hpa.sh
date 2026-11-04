#!/bin/bash
set -e

NAMESPACE="checkout"
HPA_NAME="checkout-hpa"

if ! kubectl get horizontalpodautoscaler "$HPA_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HorizontalPodAutoscaler '$HPA_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

HPA=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA_NAME" -n "$NAMESPACE" -o json)

TARGET_KIND=$(echo "$HPA" | jq -r '.spec.scaleTargetRef.kind // empty')
TARGET_NAME=$(echo "$HPA" | jq -r '.spec.scaleTargetRef.name // empty')
if [[ "$TARGET_KIND" != "Deployment" ]] || [[ "$TARGET_NAME" != "checkout-api" ]]; then
    echo "❌ Incorrect scale target. Expected Deployment/checkout-api, got '$TARGET_KIND/$TARGET_NAME'"
    exit 1
fi

MIN=$(echo "$HPA" | jq -r '.spec.minReplicas // empty')
MAX=$(echo "$HPA" | jq -r '.spec.maxReplicas // empty')
if [[ "$MIN" != "2" ]]; then
    echo "❌ Incorrect minReplicas. Expected '2', got '${MIN:-<none>}'"
    exit 1
fi
if [[ "$MAX" != "8" ]]; then
    echo "❌ Incorrect maxReplicas. Expected '8', got '${MAX:-<none>}'"
    exit 1
fi

echo "✅ HorizontalPodAutoscaler '$HPA_NAME' scales Deployment 'checkout-api' between 2 and 8 replicas"
exit 0
