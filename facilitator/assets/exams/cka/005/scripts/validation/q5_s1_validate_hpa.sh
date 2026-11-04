#!/bin/bash
set -e

NAMESPACE="scale-web"
HPA="storefront-hpa"

if ! kubectl get horizontalpodautoscaler "$HPA" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HorizontalPodAutoscaler '$HPA' not found in namespace '$NAMESPACE'"
    exit 1
fi

TARGET_KIND=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" -o jsonpath='{.spec.scaleTargetRef.kind}')
TARGET_NAME=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" -o jsonpath='{.spec.scaleTargetRef.name}')
if [[ "$TARGET_KIND" != "Deployment" || "$TARGET_NAME" != "storefront" ]]; then
    echo "❌ '$HPA' targets '$TARGET_KIND/$TARGET_NAME', expected 'Deployment/storefront'"
    exit 1
fi

MIN=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" -o jsonpath='{.spec.minReplicas}')
MAX=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" -o jsonpath='{.spec.maxReplicas}')
if [[ "$MIN" != "3" || "$MAX" != "12" ]]; then
    echo "❌ '$HPA' scales between '$MIN' and '$MAX', expected '3' and '12'"
    exit 1
fi

echo "✅ '$HPA' targets Deployment/storefront and scales between 3 and 12"
exit 0
