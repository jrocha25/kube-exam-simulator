#!/bin/bash
set -e

NAMESPACE="edge-front"
ROUTE="inventory-route"
GATEWAY="front-gw"
HOSTNAME_VALUE="inventory.helioscale.io"
BACKEND_NAMESPACE="backend-store"
SERVICE="inventory-svc"

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

RULE=$(echo "$SPEC" | jq --arg s "$SERVICE" --arg ns "$BACKEND_NAMESPACE" '[.spec.rules // [] | .[]
    | select([(.matches // [])[] | select(.path.type == "PathPrefix" and .path.value == "/")] | length > 0)
    | select([(.backendRefs // [])[] | select(.name == $s and .namespace == $ns and .port == 80)] | length > 0)] | length')
if [[ "$RULE" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' must route the PathPrefix '/' to '$BACKEND_NAMESPACE/$SERVICE' on port 80, with the namespace spelled out in the backendRef"
    exit 1
fi

echo "✅ HTTPRoute '$ROUTE' points at the Service '$BACKEND_NAMESPACE/$SERVICE'"
exit 0
