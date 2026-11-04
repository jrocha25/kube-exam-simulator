#!/bin/bash
set -e

NAMESPACE="edge-shop"
ROUTE="shop-route"

RULE=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r '[.spec.rules[]? | select(any(.matches[]?; .path.type=="PathPrefix" and .path.value=="/api"))][0] // empty')
if [[ -z "$RULE" ]]; then
    echo "❌ '$ROUTE' has no rule matching the path prefix '/api'"
    exit 1
fi

BACKEND=$(echo "$RULE" | jq -r '[.backendRefs[]? | select(.name=="shop-api" and .port==80)] | length')
if [[ "$BACKEND" == "0" ]]; then
    echo "❌ The '/api' rule does not route to the Service 'shop-api' on port 80"
    exit 1
fi

REWRITE=$(echo "$RULE" | jq -r '[.filters[]? | select(.type=="URLRewrite" and .urlRewrite.path.type=="ReplacePrefixMatch" and .urlRewrite.path.replacePrefixMatch=="/")] | length')
if [[ "$REWRITE" == "0" ]]; then
    echo "❌ The '/api' rule does not replace the matched prefix with '/'"
    exit 1
fi

echo "✅ The '/api' rule rewrites the prefix and routes to 'shop-api'"
exit 0
