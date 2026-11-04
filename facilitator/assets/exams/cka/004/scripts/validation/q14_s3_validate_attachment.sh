#!/bin/bash
set -e

ROUTE_NAMESPACE="team-orders"
ROUTE="orders-route"
GATEWAY_NAMESPACE="edge-shared"
GATEWAY="shared-gw"

if ! kubectl get httproute "$ROUTE" -n "$ROUTE_NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$ROUTE_NAMESPACE'"
    exit 1
fi

ACCEPTED=""
ATTACHED="0"
for _ in $(seq 1 12); do
    ACCEPTED=$(kubectl get httproute "$ROUTE" -n "$ROUTE_NAMESPACE" -o json \
        | jq -r '[.status.parents[]? | .conditions[]? | select(.type == "Accepted" and .status == "True")] | length' 2>/dev/null || true)
    ATTACHED=$(kubectl get gateway "$GATEWAY" -n "$GATEWAY_NAMESPACE" -o json \
        | jq -r '[.status.listeners[]? | select(.name == "partners") | .attachedRoutes] | first // 0' 2>/dev/null || true)
    if [[ -n "$ACCEPTED" ]] && [[ "$ACCEPTED" != "0" ]] && [[ "${ATTACHED:-0}" -ge 1 ]]; then
        break
    fi
    sleep 5
done

if [[ -z "$ACCEPTED" ]] || [[ "$ACCEPTED" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' was not accepted by '$GATEWAY_NAMESPACE/$GATEWAY'"
    exit 1
fi

if [[ "${ATTACHED:-0}" -lt 1 ]]; then
    echo "❌ The 'partners' listener of '$GATEWAY' reports ${ATTACHED:-0} attached routes"
    exit 1
fi

echo "✅ The cross namespace HTTPRoute is attached to the 'partners' listener"
exit 0
