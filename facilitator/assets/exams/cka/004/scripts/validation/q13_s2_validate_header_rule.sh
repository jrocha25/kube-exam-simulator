#!/bin/bash
set -e

NAMESPACE="edge-canary"
ROUTE="pay-route"
HEADER_NAME="x-canary"
HEADER_VALUE="always"
CANARY_SERVICE="pay-canary"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

MATCHES=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json \
    | jq --arg n "$HEADER_NAME" --arg v "$HEADER_VALUE" --arg s "$CANARY_SERVICE" '[.spec.rules // [] | .[]
        | select([(.matches // [])[] | (.headers // [])[]
            | select((.name | ascii_downcase) == $n and .value == $v)] | length > 0)
        | select((.backendRefs // [] | length) == 1)
        | select([(.backendRefs // [])[] | select(.name == $s and .port == 80)] | length == 1)] | length')

if [[ "$MATCHES" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' has no rule sending requests carrying '$HEADER_NAME: $HEADER_VALUE' to '$CANARY_SERVICE' only"
    exit 1
fi

echo "✅ Requests carrying '$HEADER_NAME: $HEADER_VALUE' are routed to '$CANARY_SERVICE'"
exit 0
