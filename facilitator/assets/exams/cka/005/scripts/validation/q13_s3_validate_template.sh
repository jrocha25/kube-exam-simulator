#!/bin/bash
set -e

CHART="/tmp/exam/q13/orderbook"

if [[ ! -d "$CHART" ]]; then
    echo "❌ The chart directory '$CHART' no longer exists"
    exit 1
fi

if [[ ! -f "$CHART/templates/deployment.yaml" || ! -f "$CHART/templates/service.yaml" ]]; then
    echo "❌ The chart must still render its Deployment and Service from its own templates"
    exit 1
fi

RENDERED=$(helm template orderbook "$CHART" 2>&1) || {
    echo "❌ 'helm template $CHART' still fails:"
    echo "$RENDERED"
    exit 1
}

# A quoted replica count is a string, which is exactly what the API server
# rejected; the rendered value has to be a bare integer.
if ! echo "$RENDERED" | grep -qE '^[[:space:]]+replicas:[[:space:]]*3[[:space:]]*$'; then
    echo "❌ The rendered Deployment does not declare an integer replica count of 3"
    echo "$RENDERED" | grep -i replicas || true
    exit 1
fi

if ! grep -q "replicaCount" "$CHART/values.yaml"; then
    echo "❌ The chart no longer reads its replica count from values.yaml"
    exit 1
fi

echo "✅ '$CHART' renders cleanly with an integer replica count of 3"
exit 0
