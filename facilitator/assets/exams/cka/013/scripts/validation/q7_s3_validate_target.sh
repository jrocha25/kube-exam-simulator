#!/bin/bash
set -e

NAMESPACE="wl-tide-prod"
HPA="prod-tide-reader"

JSON=$(kubectl get hpa "$HPA" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ HorizontalPodAutoscaler '$HPA' not found in '$NAMESPACE'"
    exit 1
fi

TARGET=$(echo "$JSON" | jq -r '.spec.scaleTargetRef | "\(.apiVersion)/\(.kind)/\(.name)"')
if [[ "$TARGET" != "apps/v1/Deployment/prod-tide-reader" ]]; then
    echo "❌ '$HPA' targets $TARGET, expected apps/v1/Deployment/prod-tide-reader"
    exit 1
fi

BOUNDS=$(echo "$JSON" | jq -r '"\(.spec.minReplicas)-\(.spec.maxReplicas)"')
if [[ "$BOUNDS" != "2-8" ]]; then
    echo "❌ '$HPA' scales between $BOUNDS replicas, expected 2-8"
    exit 1
fi

METRIC=$(echo "$JSON" | jq -c '[.spec.metrics[]? | select(.type == "Resource")
    | {name: .resource.name, type: .resource.target.type, value: .resource.target.averageUtilization}]')
if [[ "$METRIC" != '[{"name":"cpu","type":"Utilization","value":65}]' ]]; then
    echo "❌ '$HPA' metrics are $METRIC, expected CPU utilization 65"
    exit 1
fi

echo "✅ '$HPA' targets prod-tide-reader, 2-8 replicas at 65% CPU"
exit 0
