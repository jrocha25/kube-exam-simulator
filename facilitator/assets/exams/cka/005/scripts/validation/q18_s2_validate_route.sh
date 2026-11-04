#!/bin/bash
set -e

NAMESPACE="edge-stuck"
ROUTE="catalog-route"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json)

HOSTNAME=$(echo "$SPEC" | jq -r '[.spec.hostnames[]? | select(. == "catalog.helioscale.io")] | length')
if [[ "$HOSTNAME" == "0" ]]; then
    echo "❌ '$ROUTE' does not serve 'catalog.helioscale.io'"
    exit 1
fi

BACKEND=$(echo "$SPEC" | jq -r '[.spec.rules[]? | .backendRefs[]? | select(.name=="catalog" and .port==80)] | length')
if [[ "$BACKEND" == "0" ]]; then
    echo "❌ '$ROUTE' does not route to the Service 'catalog' on port 80"
    exit 1
fi

PARENT=$(echo "$SPEC" | jq -r '[.spec.parentRefs[]? | select(.name=="edge-gw")] | length')
if [[ "$PARENT" == "0" ]]; then
    echo "❌ '$ROUTE' does not reference the Gateway 'edge-gw'"
    exit 1
fi

echo "✅ '$ROUTE' serves 'catalog.helioscale.io' and routes to the catalog Service"
exit 0
