#!/bin/bash
set -e

NAMESPACE="hpa-crane"
HPA="crane-telemetry"

JSON=$(kubectl get hpa.v2.autoscaling "$HPA" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ HorizontalPodAutoscaler '$HPA' not found in '$NAMESPACE'"
    exit 1
fi

DOWN=$(echo "$JSON" | jq -c '.spec.behavior.scaleDown // {}')
if [[ "$(echo "$DOWN" | jq -r '.stabilizationWindowSeconds')" != "45" ]]; then
    echo "❌ The scale-down stabilization window of '$HPA' is not 45 seconds: $DOWN"
    exit 1
fi
if ! echo "$DOWN" | jq -e '(.policies | length) == 1
        and .policies[0].type == "Pods"
        and .policies[0].value == 1
        and .policies[0].periodSeconds == 60' >/dev/null; then
    echo "❌ '$HPA' must scale down by at most 1 Pod per 60 seconds, with that as its only policy: $DOWN"
    exit 1
fi

echo "✅ '$HPA' scales down after a 45s window, at most 1 Pod per minute"
exit 0
