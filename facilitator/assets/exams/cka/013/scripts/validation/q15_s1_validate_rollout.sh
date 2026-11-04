#!/bin/bash
set -e

NAMESPACE="ts-cargo"
DEPLOYMENT="cargo-api"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Deployment '$DEPLOYMENT' not found in '$NAMESPACE'"
    exit 1
fi

if [[ "$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')" != "2" ]]; then
    echo "❌ '$DEPLOYMENT' no longer declares 2 replicas"
    exit 1
fi

# Complete means every replica is on the latest template and nothing old is left.
for _ in $(seq 1 12); do
    STATUS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq -r '
        if .status.observedGeneration == .metadata.generation then
          "\(.status.replicas // 0)/\(.status.updatedReplicas // 0)/\(.status.readyReplicas // 0)/\(.status.availableReplicas // 0)"
        else "stale" end')
    [[ "$STATUS" == "2/2/2/2" ]] && break
    sleep 5
done
if [[ "$STATUS" != "2/2/2/2" ]]; then
    echo "❌ The rollout is not complete (total/updated/ready/available = $STATUS)"
    exit 1
fi

echo "✅ '$DEPLOYMENT' finished rolling out: 2 updated, ready replicas"
exit 0
