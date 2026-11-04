#!/bin/bash
set -e

NAMESPACE="scale-web"
HPA="storefront-hpa"

SPEC=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$SPEC" ]]; then
    echo "❌ HorizontalPodAutoscaler '$HPA' not found in namespace '$NAMESPACE'"
    exit 1
fi

WINDOW=$(echo "$SPEC" | jq -r '.spec.behavior.scaleUp.stabilizationWindowSeconds // empty')
if [[ "$WINDOW" != "0" ]]; then
    echo "❌ Expected a scale up stabilization window of '0', got '${WINDOW:-<none>}'"
    exit 1
fi

SELECT=$(echo "$SPEC" | jq -r '.spec.behavior.scaleUp.selectPolicy // empty')
if [[ "$SELECT" != "Max" ]]; then
    echo "❌ Expected scale up selectPolicy 'Max', got '${SELECT:-<none>}'"
    exit 1
fi

PODS=$(echo "$SPEC" | jq -r '[.spec.behavior.scaleUp.policies[]? | select(.type=="Pods" and .value==4 and .periodSeconds==60)] | length')
if [[ "$PODS" != "1" ]]; then
    echo "❌ Expected a scale up policy adding 4 Pods every 60 seconds"
    exit 1
fi

PERCENT=$(echo "$SPEC" | jq -r '[.spec.behavior.scaleUp.policies[]? | select(.type=="Percent" and .value==100 and .periodSeconds==60)] | length')
if [[ "$PERCENT" != "1" ]]; then
    echo "❌ Expected a scale up policy adding 100 percent every 60 seconds"
    exit 1
fi

echo "✅ '$HPA' has the required scale up behavior"
exit 0
