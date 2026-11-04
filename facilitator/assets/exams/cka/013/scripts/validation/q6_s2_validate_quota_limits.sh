#!/bin/bash
set -e

NAMESPACE="wl-harbor"

QUOTA=$(kubectl get resourcequota harbor-quota -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$QUOTA" ]]; then
    echo "❌ ResourceQuota 'harbor-quota' not found in '$NAMESPACE'"
    exit 1
fi

# Compare as quantities the API server normalised, not as the strings typed.
HARD=$(echo "$QUOTA" | jq -c '.spec.hard')
WANT='{"limits.cpu":"2","limits.memory":"2Gi","pods":"6","requests.cpu":"1","requests.memory":"1Gi"}'
if [[ "$(echo "$HARD" | jq -S -c .)" != "$(echo "$WANT" | jq -S -c .)" ]]; then
    echo "❌ harbor-quota limits $HARD, expected $WANT"
    exit 1
fi

LR=$(kubectl get limitrange harbor-defaults -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$LR" ]]; then
    echo "❌ LimitRange 'harbor-defaults' not found in '$NAMESPACE'"
    exit 1
fi

ITEM=$(echo "$LR" | jq -c '[.spec.limits[] | select(.type == "Container")] | first // empty')
if [[ -z "$ITEM" ]]; then
    echo "❌ harbor-defaults has no limit of type Container"
    exit 1
fi
check() {
    local path="$1" want="$2" got
    got=$(echo "$ITEM" | jq -r "$path // empty")
    if [[ "$got" != "$want" ]]; then
        echo "❌ harbor-defaults $path is '${got:-unset}', expected '$want'"
        exit 1
    fi
}
check '.defaultRequest.cpu' 50m
check '.defaultRequest.memory' 64Mi
check '.default.cpu' 200m
check '.default.memory' 128Mi

echo "✅ harbor-quota and harbor-defaults are configured as asked"
exit 0
