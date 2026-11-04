#!/bin/bash
set -e

NAMESPACE="wl-harbor"
DEPLOYMENT="manifest-api"
STATE_FILE=/tmp/exam/q6/template-hash

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in '$NAMESPACE'"
    exit 1
fi

if [[ "$(echo "$JSON" | jq -r '.spec.template.spec.containers[0].image')" != "busybox:1.36" ]]; then
    echo "❌ '$DEPLOYMENT' no longer runs busybox:1.36"
    exit 1
fi
if [[ "$(echo "$JSON" | jq '[.spec.template.spec.containers[] | .resources // {} | length] | add')" != "0" ]]; then
    echo "❌ '$DEPLOYMENT' sets resources itself; the LimitRange must supply them"
    exit 1
fi

for _ in $(seq 1 12); do
    STATUS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}/{.status.updatedReplicas}/{.status.replicas}')
    [[ "$STATUS" == "2/2/2" ]] && break
    sleep 5
done
if [[ "$STATUS" != "2/2/2" ]]; then
    echo "❌ '$DEPLOYMENT' is not fully rolled out (ready/updated/total = $STATUS)"
    exit 1
fi

# Old Pods that are already terminating do not count: busybox's sh ignores
# SIGTERM, so a correct rollout leaves them around for the 30s grace period.
PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -o json)
if [[ -s "$STATE_FILE" ]] && echo "$PODS" | jq -e --arg h "$(cat "$STATE_FILE")" \
        '.items[] | select(.metadata.deletionTimestamp == null and .metadata.labels["pod-template-hash"] == $h)' >/dev/null; then
    echo "❌ Pods from before the guardrails are still running; they were never re-admitted"
    exit 1
fi

# A hand-written limit with no request defaults the request to the limit, so this
# asymmetric pair on the running Pods can only have come from the LimitRange.
BAD=$(echo "$PODS" | jq '[.items[] | select(.metadata.deletionTimestamp == null) | .spec.containers[0].resources
    | select(.requests.cpu != "50m" or .requests.memory != "64Mi" or .limits.cpu != "200m" or .limits.memory != "128Mi")] | length')
if [[ "$BAD" != "0" ]]; then
    echo "❌ $BAD running Pod(s) did not get the LimitRange defaults"
    exit 1
fi

echo "✅ '$DEPLOYMENT' was re-admitted with the LimitRange defaults and has 2 ready replicas"
exit 0
