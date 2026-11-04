#!/bin/bash
set -e

NAMESPACE="edge-canary"
ROUTE="pay-route"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

MATCHES=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json \
    | jq '[.spec.rules // [] | .[]
        | select((.backendRefs // [] | length) == 2)
        | select([(.backendRefs // [])[] | select(.name == "pay-stable" and .port == 80 and .weight == 90)] | length == 1)
        | select([(.backendRefs // [])[] | select(.name == "pay-canary" and .port == 80 and .weight == 10)] | length == 1)] | length')

if [[ "$MATCHES" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' has no rule splitting traffic 90/10 between 'pay-stable' and 'pay-canary' on port 80"
    exit 1
fi

echo "✅ HTTPRoute '$ROUTE' splits traffic 90/10 between 'pay-stable' and 'pay-canary'"
exit 0
