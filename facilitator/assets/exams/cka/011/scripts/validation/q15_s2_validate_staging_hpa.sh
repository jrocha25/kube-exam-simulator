#!/bin/bash
set -e

# Graded on the autoscaler's spec, not on how many replicas it produced. If the
# candidate also solved question 3 the Metrics API is live and the HPA will move
# the replica count around; asserting a count here would race that.

NAMESPACE="kustom-flight-staging"
HPA="flightboard"
MAX="4"

if ! kubectl get horizontalpodautoscaler "$HPA" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ HorizontalPodAutoscaler '$HPA' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get horizontalpodautoscaler "$HPA" -n "$NAMESPACE" -o json)

TARGET_KIND=$(jq -r '.spec.scaleTargetRef.kind // ""' <<<"$JSON")
TARGET_NAME=$(jq -r '.spec.scaleTargetRef.name // ""' <<<"$JSON")
if [[ "$TARGET_KIND" != "Deployment" || "$TARGET_NAME" != "flightboard" ]]; then
    echo "❌ '$HPA' targets ${TARGET_KIND:-nothing}/${TARGET_NAME:-nothing}, expected Deployment/flightboard"
    exit 1
fi

MIN=$(jq -r '.spec.minReplicas // ""' <<<"$JSON")
GOT_MAX=$(jq -r '.spec.maxReplicas // ""' <<<"$JSON")
if [[ "$MIN" != "2" ]]; then
    echo "❌ '$HPA' has minReplicas ${MIN:-unset}, expected 2"
    exit 1
fi
if [[ "$GOT_MAX" != "$MAX" ]]; then
    echo "❌ '$HPA' has maxReplicas ${GOT_MAX:-unset}, expected $MAX"
    exit 1
fi

if ! jq -e '(.spec.metrics // []) | any(
        .type == "Resource"
        and .resource.name == "cpu"
        and .resource.target.type == "Utilization"
        and .resource.target.averageUtilization == 60)' <<<"$JSON" >/dev/null; then
    echo "❌ '$HPA' does not scale on 60% average CPU utilisation"
    exit 1
fi

echo "✅ The staging autoscaler runs 2 to 4 replicas at 60% CPU"
exit 0
