#!/bin/bash
set -e

NAMESPACE="wl-tide-prod"
HPA="prod-tide-reader"

JSON=$(kubectl get hpa "$HPA" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ HorizontalPodAutoscaler '$HPA' not found in '$NAMESPACE'"
    exit 1
fi

# Policies are compared as a set: their order carries no meaning.
DOWN=$(echo "$JSON" | jq -c '.spec.behavior.scaleDown // {} | {
    window: .stabilizationWindowSeconds,
    select: .selectPolicy,
    policies: (.policies // [] | sort_by(.type))}')
WANT_DOWN='{"window":300,"select":"Min","policies":[{"periodSeconds":60,"type":"Percent","value":20},{"periodSeconds":60,"type":"Pods","value":1}]}'
if [[ "$(echo "$DOWN" | jq -S -c .)" != "$(echo "$WANT_DOWN" | jq -S -c .)" ]]; then
    echo "❌ scaleDown is $DOWN"
    echo "   expected $WANT_DOWN"
    exit 1
fi

UP=$(echo "$JSON" | jq -c '.spec.behavior.scaleUp // {} | {
    window: .stabilizationWindowSeconds,
    select: (.selectPolicy // "Max"),
    policies: (.policies // [] | sort_by(.type))}')
WANT_UP='{"window":0,"select":"Max","policies":[{"periodSeconds":30,"type":"Percent","value":50}]}'
if [[ "$(echo "$UP" | jq -S -c .)" != "$(echo "$WANT_UP" | jq -S -c .)" ]]; then
    echo "❌ scaleUp is $UP"
    echo "   expected $WANT_UP"
    exit 1
fi

echo "✅ '$HPA' has the exact scale-up and scale-down behavior"
exit 0
