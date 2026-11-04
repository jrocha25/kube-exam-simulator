#!/bin/bash
set -e

NAMESPACE="ts-cargo"
DEPLOYMENT="cargo-api"

STATUS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.updatedReplicas}/{.status.readyReplicas}' 2>/dev/null || true)
if [[ "$STATUS" != "2/2" ]]; then
    echo "❌ '$DEPLOYMENT' has not finished rolling out"
    exit 1
fi

CONTAINER=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq -c '.spec.template.spec.containers[0]')
if [[ "$(echo "$CONTAINER" | jq '(.livenessProbe != null) and (.readinessProbe != null)')" != "true" ]]; then
    echo "❌ '$DEPLOYMENT' no longer has both a liveness and a readiness probe"
    exit 1
fi

# Stable: no container restarts over 20 seconds.
restarts() {
    kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -o json \
        | jq '[.items[] | select(.metadata.deletionTimestamp == null) | .status.containerStatuses[]?.restartCount] | add // 0'
}
BEFORE=$(restarts)
sleep 20
AFTER=$(restarts)
if [[ "$BEFORE" != "$AFTER" ]]; then
    echo "❌ The Pods restarted during a 20 second window ($BEFORE → $AFTER restarts)"
    exit 1
fi

echo "✅ Both probes are present and the Pods are stable"
exit 0
