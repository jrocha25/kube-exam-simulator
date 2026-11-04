#!/bin/bash
set -e

NAMESPACE="scale-batch"
HPA="render-worker-hpa"

if ! kubectl get horizontalpodautoscaler "$HPA" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HorizontalPodAutoscaler '$HPA' not found in namespace '$NAMESPACE'"
    exit 1
fi

MIN=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" -o jsonpath='{.spec.minReplicas}')
MAX=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" -o jsonpath='{.spec.maxReplicas}')
TARGET=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" -o json \
    | jq -r '[.spec.metrics[]? | select(.resource.name=="cpu") | .resource.target.averageUtilization][0] // empty')
if [[ "$MIN" != "2" || "$MAX" != "10" || "$TARGET" != "60" ]]; then
    echo "❌ '$HPA' was changed: expected min 2, max 10 and a 60% CPU target, got '$MIN', '$MAX', '${TARGET:-<none>}'"
    exit 1
fi

# ScalingActive is the definitive signal that the autoscaler can read a
# utilization percentage; it stays False for as long as the target has no request
# to compute a percentage against. Metrics arrive a scrape cycle at a time, so
# give it a bounded moment rather than judging the first reading.
STATUS=""
for _ in $(seq 1 12); do
    STATUS=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].status}' 2>/dev/null || true)
    if [[ "$STATUS" == "True" ]]; then
        break
    fi
    sleep 5
done

if [[ "$STATUS" != "True" ]]; then
    echo "❌ '$HPA' still reports ScalingActive='${STATUS:-<none>}'; it cannot compute a CPU utilization"
    exit 1
fi

echo "✅ '$HPA' can read CPU utilization and is actively scaling"
exit 0
