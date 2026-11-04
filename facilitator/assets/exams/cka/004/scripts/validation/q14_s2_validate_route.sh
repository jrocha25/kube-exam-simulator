#!/bin/bash
set -e

NAMESPACE="team-orders"
ROUTE="orders-route"
GATEWAY="shared-gw"
GATEWAY_NAMESPACE="edge-shared"
HOSTNAME_VALUE="partners.helioscale.io"
SERVICE="orders-svc"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json)

PARENT=$(echo "$SPEC" | jq --arg g "$GATEWAY" --arg ns "$GATEWAY_NAMESPACE" '[.spec.parentRefs // [] | .[]
    | select(.name == $g and .namespace == $ns and .sectionName == "partners")] | length')
if [[ "$PARENT" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' must reference the 'partners' listener of '$GATEWAY_NAMESPACE/$GATEWAY' (name, namespace and sectionName)"
    exit 1
fi

HOST=$(echo "$SPEC" | jq -r --arg h "$HOSTNAME_VALUE" '[.spec.hostnames // [] | .[] | select(. == $h)] | first // empty')
if [[ "$HOST" != "$HOSTNAME_VALUE" ]]; then
    echo "❌ HTTPRoute '$ROUTE' must serve the hostname '$HOSTNAME_VALUE'"
    exit 1
fi

RULE=$(echo "$SPEC" | jq --arg s "$SERVICE" '[.spec.rules // [] | .[]
    | select([(.matches // [])[] | select(.path.type == "PathPrefix" and .path.value == "/")] | length > 0)
    | select([(.backendRefs // [])[] | select(.name == $s and .port == 80)] | length > 0)] | length')
if [[ "$RULE" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' has no rule matching the PathPrefix '/' and routing to '$SERVICE' on port 80"
    exit 1
fi

echo "✅ HTTPRoute '$ROUTE' targets the 'partners' listener of '$GATEWAY_NAMESPACE/$GATEWAY'"
exit 0
