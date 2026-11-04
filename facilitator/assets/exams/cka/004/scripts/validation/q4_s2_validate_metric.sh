#!/bin/bash
set -e

NAMESPACE="checkout"
HPA_NAME="checkout-hpa"

if ! kubectl get horizontalpodautoscaler "$HPA_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HorizontalPodAutoscaler '$HPA_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

MATCHES=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA_NAME" -n "$NAMESPACE" -o json \
    | jq '[.spec.metrics // [] | .[]
        | select(.type == "Resource")
        | select(.resource.name == "cpu")
        | select(.resource.target.type == "Utilization")
        | select(.resource.target.averageUtilization == 60)] | length')

if [[ "$MATCHES" == "0" ]]; then
    echo "❌ '$HPA_NAME' has no Resource metric targeting 60% average CPU utilization"
    exit 1
fi

echo "✅ '$HPA_NAME' scales on 60% average CPU utilization"
exit 0
