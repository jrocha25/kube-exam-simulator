#!/bin/bash
set -e

NAMESPACE="scale-web"
HPA="storefront-hpa"

METRICS=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$METRICS" ]]; then
    echo "❌ HorizontalPodAutoscaler '$HPA' not found in namespace '$NAMESPACE'"
    exit 1
fi

CPU=$(echo "$METRICS" | jq -r '[.spec.metrics[]? | select(.type=="Resource" and .resource.name=="cpu" and .resource.target.type=="Utilization") | .resource.target.averageUtilization][0] // empty')
if [[ "$CPU" != "70" ]]; then
    echo "❌ Expected a CPU utilization target of '70', got '${CPU:-<none>}'"
    exit 1
fi

MEM=$(echo "$METRICS" | jq -r '[.spec.metrics[]? | select(.type=="Resource" and .resource.name=="memory" and .resource.target.type=="Utilization") | .resource.target.averageUtilization][0] // empty')
if [[ "$MEM" != "80" ]]; then
    echo "❌ Expected a memory utilization target of '80', got '${MEM:-<none>}'"
    exit 1
fi

echo "✅ '$HPA' scales on 70% CPU and 80% memory utilization"
exit 0
