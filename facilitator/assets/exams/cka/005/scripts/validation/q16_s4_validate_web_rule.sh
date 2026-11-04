#!/bin/bash
set -e

NAMESPACE="edge-shop"
ROUTE="shop-route"

RULE=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r '[.spec.rules[]? | select(any(.matches[]?; .path.type=="PathPrefix" and .path.value=="/"))][0] // empty')
if [[ -z "$RULE" ]]; then
    echo "❌ '$ROUTE' has no rule matching the path prefix '/'"
    exit 1
fi

BACKEND=$(echo "$RULE" | jq -r '[.backendRefs[]? | select(.name=="shop-web" and .port==80)] | length')
if [[ "$BACKEND" == "0" ]]; then
    echo "❌ The '/' rule does not route to the Service 'shop-web' on port 80"
    exit 1
fi

HEADER=$(echo "$RULE" | jq -r '[.filters[]? | select(.type=="RequestHeaderModifier") | .requestHeaderModifier.add[]? | select((.name | ascii_downcase)=="x-edge" and .value=="helioscale")] | length')
if [[ "$HEADER" == "0" ]]; then
    echo "❌ The '/' rule does not add the header 'X-Edge: helioscale'"
    exit 1
fi

echo "✅ The '/' rule adds the edge header and routes to 'shop-web'"
exit 0
