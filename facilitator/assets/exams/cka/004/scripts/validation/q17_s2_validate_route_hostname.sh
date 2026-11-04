#!/bin/bash
set -e

NAMESPACE="edge-broken"
ROUTE="shop-route"
GATEWAY="shop-gw"
HOSTNAME_VALUE="shop.helioscale.io"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json)

PARENT=$(echo "$SPEC" | jq --arg g "$GATEWAY" '[.spec.parentRefs // [] | .[] | select(.name == $g)] | length')
if [[ "$PARENT" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' must stay attached to the Gateway '$GATEWAY'"
    exit 1
fi

HOSTNAMES=$(echo "$SPEC" | jq -r '[.spec.hostnames // [] | .[]] | sort | join(",")')
if [[ "$HOSTNAMES" != "$HOSTNAME_VALUE" ]]; then
    echo "❌ HTTPRoute '$ROUTE' must serve exactly the hostname '$HOSTNAME_VALUE' (got: '${HOSTNAMES:-<none>}')"
    exit 1
fi

echo "✅ HTTPRoute '$ROUTE' serves '$HOSTNAME_VALUE' on the Gateway '$GATEWAY'"
exit 0
