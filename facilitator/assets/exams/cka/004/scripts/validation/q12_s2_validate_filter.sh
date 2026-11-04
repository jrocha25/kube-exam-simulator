#!/bin/bash
set -e

NAMESPACE="edge-migrate"
ROUTE="web-route"
HEADER_NAME="x-helioscale-edge"
HEADER_VALUE="gateway"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json)

TOTAL=$(echo "$SPEC" | jq '.spec.rules // [] | length')
if [[ "$TOTAL" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' has no rules"
    exit 1
fi

WITH_FILTER=$(echo "$SPEC" | jq --arg n "$HEADER_NAME" --arg v "$HEADER_VALUE" '[.spec.rules // [] | .[]
    | select([(.filters // [])[]
        | select(.type == "RequestHeaderModifier")
        | (.requestHeaderModifier.set // [])[]
        | select((.name | ascii_downcase) == $n and .value == $v)] | length > 0)] | length')

if [[ "$WITH_FILTER" != "$TOTAL" ]]; then
    echo "❌ Every rule must set the request header '$HEADER_NAME: $HEADER_VALUE' ($WITH_FILTER of $TOTAL rules do)"
    exit 1
fi

echo "✅ Every rule of '$ROUTE' sets the request header '$HEADER_NAME: $HEADER_VALUE'"
exit 0
