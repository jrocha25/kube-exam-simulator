#!/bin/bash
set -e

NAMESPACE="edge-canary"
ROUTE="pay-route"
GATEWAY="canary-gw"
HOSTNAME_VALUE="pay.helioscale.io"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json)

PARENT=$(echo "$SPEC" | jq --arg g "$GATEWAY" '[.spec.parentRefs // [] | .[] | select(.name == $g)] | length')
if [[ "$PARENT" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' does not reference the Gateway '$GATEWAY' as a parent"
    exit 1
fi

HOST=$(echo "$SPEC" | jq -r --arg h "$HOSTNAME_VALUE" '[.spec.hostnames // [] | .[] | select(. == $h)] | first // empty')
if [[ "$HOST" != "$HOSTNAME_VALUE" ]]; then
    echo "❌ HTTPRoute '$ROUTE' must serve the hostname '$HOSTNAME_VALUE'"
    exit 1
fi

ACCEPTED=""
for _ in $(seq 1 12); do
    ACCEPTED=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json \
        | jq -r '[.status.parents[]? | .conditions[]? | select(.type == "Accepted" and .status == "True")] | length' 2>/dev/null || true)
    if [[ -n "$ACCEPTED" ]] && [[ "$ACCEPTED" != "0" ]]; then
        break
    fi
    sleep 5
done

if [[ -z "$ACCEPTED" ]] || [[ "$ACCEPTED" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' was not accepted by the Gateway"
    exit 1
fi

echo "✅ HTTPRoute '$ROUTE' is attached to '$GATEWAY' for '$HOSTNAME_VALUE'"
exit 0
