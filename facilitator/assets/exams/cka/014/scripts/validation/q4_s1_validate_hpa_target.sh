#!/bin/bash
set -e

NAMESPACE="hpa-crane"
HPA="crane-telemetry"

JSON=$(kubectl get hpa.v2.autoscaling "$HPA" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ HorizontalPodAutoscaler '$HPA' not found in '$NAMESPACE'"
    exit 1
fi

if ! echo "$JSON" | jq -e '.spec.scaleTargetRef.kind == "Deployment"
        and .spec.scaleTargetRef.name == "crane-telemetry"
        and ((.spec.scaleTargetRef.apiVersion // "apps/v1") == "apps/v1")' >/dev/null; then
    echo "❌ '$HPA' does not target the Deployment crane-telemetry"
    exit 1
fi

if ! echo "$JSON" | jq -e '.spec.minReplicas == 2 and .spec.maxReplicas == 6' >/dev/null; then
    echo "❌ '$HPA' must scale between 2 and 6 replicas"
    exit 1
fi

if ! echo "$JSON" | jq -e '(.spec.metrics | length) == 1
        and .spec.metrics[0].type == "Resource"
        and .spec.metrics[0].resource.name == "cpu"
        and .spec.metrics[0].resource.target.type == "Utilization"
        and .spec.metrics[0].resource.target.averageUtilization == 65' >/dev/null; then
    echo "❌ '$HPA' must have exactly one metric: average CPU utilization of 65%"
    exit 1
fi

echo "✅ '$HPA' targets crane-telemetry at 65% CPU between 2 and 6 replicas"
exit 0
