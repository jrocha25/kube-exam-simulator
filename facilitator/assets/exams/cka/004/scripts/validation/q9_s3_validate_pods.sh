#!/bin/bash
set -e

NAMESPACE="priority"
DEPLOYMENT="edge-proxy"
EXPECTED_PRIORITY="44999"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

MATCHING=0
for _ in $(seq 1 12); do
    MATCHING=$(kubectl get pods -n "$NAMESPACE" -l app=edge-proxy -o json \
        | jq --argjson p "$EXPECTED_PRIORITY" '[.items[]
            | select(.status.phase == "Running")
            | select(.spec.priority == $p)] | length')
    if [[ "$MATCHING" -ge 2 ]]; then
        break
    fi
    sleep 5
done

if [[ "$MATCHING" -lt 2 ]]; then
    echo "❌ Expected 2 running Pods with priority $EXPECTED_PRIORITY, found $MATCHING"
    exit 1
fi

echo "✅ The '$DEPLOYMENT' Pods run with priority $EXPECTED_PRIORITY"
exit 0
