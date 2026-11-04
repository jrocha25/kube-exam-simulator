#!/bin/bash
set -e

NAMESPACE="scale-batch"
DEPLOYMENT="render-worker"
HPA="render-worker-hpa"

# Reaching minReplicas proves nothing on its own: an autoscaler raises its target
# to the minimum even while its metrics are unreadable. What has to be true is
# that the autoscaler is now reading an actual utilization figure back.
CURRENT=""
for _ in $(seq 1 12); do
    CURRENT=$(kubectl get horizontalpodautoscaler.v2.autoscaling "$HPA" -n "$NAMESPACE" -o json 2>/dev/null \
        | jq -r '[.status.currentMetrics[]? | select(.resource.name=="cpu") | .resource.current.averageUtilization] | map(select(. != null)) | .[0] // empty')
    if [[ -n "$CURRENT" ]]; then
        break
    fi
    sleep 5
done

if [[ -z "$CURRENT" ]]; then
    echo "❌ '$HPA' reports no current CPU utilization"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
if [[ -z "$READY" || "$READY" -lt 2 ]]; then
    echo "❌ '$DEPLOYMENT' has ${READY:-0} ready replicas, expected at least 2"
    exit 1
fi

echo "✅ '$HPA' reports ${CURRENT}% CPU utilization across $READY ready replicas"
exit 0
