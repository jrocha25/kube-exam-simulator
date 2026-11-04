#!/bin/bash
set -e

NAMESPACE="edge-shop"
ROUTE="shop-route"
GATEWAY="shop-gw"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

PARENT=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json \
    | jq -r --arg g "$GATEWAY" '[.spec.parentRefs[]? | select(.name==$g)] | length')
if [[ "$PARENT" == "0" ]]; then
    echo "❌ '$ROUTE' does not reference the Gateway '$GATEWAY'"
    exit 1
fi

HOSTNAME=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json \
    | jq -r '[.spec.hostnames[]? | select(. == "shop.helioscale.io")] | length')
if [[ "$HOSTNAME" == "0" ]]; then
    echo "❌ '$ROUTE' does not serve the hostname 'shop.helioscale.io'"
    exit 1
fi

ACCEPTED=""
for _ in $(seq 1 12); do
    ACCEPTED=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json \
        | jq -r --arg g "$GATEWAY" '[.status.parents[]? | select(.parentRef.name==$g) | .conditions[]? | select(.type=="Accepted") | .status][0] // empty')
    if [[ "$ACCEPTED" == "True" ]]; then
        break
    fi
    sleep 5
done

if [[ "$ACCEPTED" != "True" ]]; then
    echo "❌ '$ROUTE' reports Accepted='${ACCEPTED:-<none>}' for '$GATEWAY'"
    exit 1
fi

echo "✅ '$ROUTE' is attached to '$GATEWAY' and serves 'shop.helioscale.io'"
exit 0
