#!/bin/bash
set -e

NAMESPACE="edge-broken"
ROUTE="shop-route"
SERVICE="shop-svc"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

RULE=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json \
    | jq --arg s "$SERVICE" '[.spec.rules // [] | .[]
        | select([(.backendRefs // [])[] | select(.name == $s and .port == 80)] | length > 0)] | length')
if [[ "$RULE" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' does not reach '$SERVICE' on the port the Service exposes"
    exit 1
fi

ACCEPTED=""
RESOLVED=""
for _ in $(seq 1 12); do
    STATUS=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json)
    ACCEPTED=$(echo "$STATUS" | jq -r '[.status.parents[]? | .conditions[]? | select(.type == "Accepted" and .status == "True")] | length')
    RESOLVED=$(echo "$STATUS" | jq -r '[.status.parents[]? | .conditions[]? | select(.type == "ResolvedRefs" and .status == "True")] | length')
    if [[ "$ACCEPTED" != "0" ]] && [[ "$RESOLVED" != "0" ]]; then
        break
    fi
    sleep 5
done

if [[ "$ACCEPTED" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' is still not accepted by the Gateway"
    exit 1
fi
if [[ "$RESOLVED" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' still cannot resolve its backend reference"
    exit 1
fi

echo "✅ HTTPRoute '$ROUTE' is accepted and its backend reference resolves"
exit 0
