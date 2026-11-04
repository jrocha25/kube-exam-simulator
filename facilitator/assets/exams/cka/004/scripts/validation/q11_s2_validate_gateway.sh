#!/bin/bash
set -e

NAMESPACE="edge-basic"
GATEWAY="edge-gw"
HOSTNAME_VALUE="search.helioscale.io"

if ! kubectl get gateway "$GATEWAY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o json)

CLASS=$(echo "$SPEC" | jq -r '.spec.gatewayClassName // empty')
if ! kubectl get gatewayclass "$CLASS" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' references the GatewayClass '${CLASS:-<none>}', which does not exist"
    exit 1
fi

LISTENERS=$(echo "$SPEC" | jq '.spec.listeners // [] | length')
if [[ "$LISTENERS" != "1" ]]; then
    echo "❌ Gateway '$GATEWAY' must declare exactly one listener (found $LISTENERS)"
    exit 1
fi

NAME=$(echo "$SPEC" | jq -r '.spec.listeners[0].name // empty')
PORT=$(echo "$SPEC" | jq -r '.spec.listeners[0].port // empty')
PROTOCOL=$(echo "$SPEC" | jq -r '.spec.listeners[0].protocol // empty')
LISTENER_HOST=$(echo "$SPEC" | jq -r '.spec.listeners[0].hostname // empty')

if [[ "$NAME" != "http" ]]; then
    echo "❌ Incorrect listener name. Expected 'http', got '${NAME:-<none>}'"
    exit 1
fi
if [[ "$PORT" != "80" ]]; then
    echo "❌ Incorrect listener port. Expected '80', got '${PORT:-<none>}'"
    exit 1
fi
if [[ "$PROTOCOL" != "HTTP" ]]; then
    echo "❌ Incorrect listener protocol. Expected 'HTTP', got '${PROTOCOL:-<none>}'"
    exit 1
fi
if [[ "$LISTENER_HOST" != "$HOSTNAME_VALUE" ]]; then
    echo "❌ Incorrect listener hostname. Expected '$HOSTNAME_VALUE', got '${LISTENER_HOST:-<none>}'"
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
    echo "❌ Gateway '$GATEWAY' is not Accepted by the controller (status: '${ACCEPTED:-<none>}')"
    exit 1
fi
if [[ "$PROGRAMMED" != "True" ]]; then
    echo "❌ Gateway '$GATEWAY' is not Programmed by the controller (status: '${PROGRAMMED:-<none>}')"
    exit 1
fi

echo "✅ Gateway '$GATEWAY' listens on $HOSTNAME_VALUE:80 and is programmed"
exit 0
