#!/bin/bash
set -e

NAMESPACE="edge-broken"
GATEWAY="shop-gw"
HOSTNAME_VALUE="shop.helioscale.io"

if ! kubectl get gateway "$GATEWAY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o json)

CLASS=$(echo "$SPEC" | jq -r '.spec.gatewayClassName // empty')
if ! kubectl get gatewayclass "$CLASS" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' references the GatewayClass '${CLASS:-<none>}', which does not exist in this cluster"
    exit 1
fi

LISTENERS=$(echo "$SPEC" | jq '.spec.listeners // [] | length')
if [[ "$LISTENERS" != "1" ]]; then
    echo "❌ Gateway '$GATEWAY' must keep exactly one listener (found $LISTENERS)"
    exit 1
fi

PORT=$(echo "$SPEC" | jq -r '.spec.listeners[0].port // empty')
PROTOCOL=$(echo "$SPEC" | jq -r '.spec.listeners[0].protocol // empty')
LISTENER_HOST=$(echo "$SPEC" | jq -r '.spec.listeners[0].hostname // empty')

if [[ "$PORT" != "80" ]] || [[ "$PROTOCOL" != "HTTP" ]]; then
    echo "❌ The listener must stay on port 80 with protocol HTTP (got: '$PROTOCOL/$PORT')"
    exit 1
fi
if [[ "$LISTENER_HOST" != "$HOSTNAME_VALUE" ]]; then
    echo "❌ The listener must serve the hostname '$HOSTNAME_VALUE' (got: '${LISTENER_HOST:-<none>}')"
    exit 1
fi

ACCEPTED=""
PROGRAMMED=""
for _ in $(seq 1 12); do
    ACCEPTED=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
    PROGRAMMED=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
    if [[ "$ACCEPTED" == "True" ]] && [[ "$PROGRAMMED" == "True" ]]; then
        break
    fi
    sleep 5
done

if [[ "$ACCEPTED" != "True" ]]; then
    echo "❌ Gateway '$GATEWAY' is not Accepted by a controller (status: '${ACCEPTED:-<none>}')"
    exit 1
fi
if [[ "$PROGRAMMED" != "True" ]]; then
    echo "❌ Gateway '$GATEWAY' is not Programmed (status: '${PROGRAMMED:-<none>}')"
    exit 1
fi

echo "✅ Gateway '$GATEWAY' is accepted and programmed for '$HOSTNAME_VALUE'"
exit 0
