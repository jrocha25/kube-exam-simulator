#!/bin/bash
set -e

NAMESPACE="edge-shop"
GATEWAY="shop-gw"

if ! kubectl get gateway "$GATEWAY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o json)

CLASS=$(echo "$SPEC" | jq -r '.spec.gatewayClassName')
if [[ "$CLASS" != "traefik" ]]; then
    echo "❌ '$GATEWAY' uses GatewayClass '$CLASS', expected 'traefik'"
    exit 1
fi

LISTENER=$(echo "$SPEC" | jq -r '[.spec.listeners[]? | select(.name=="web")][0] // empty')
if [[ -z "$LISTENER" ]]; then
    echo "❌ '$GATEWAY' has no listener named 'web'"
    exit 1
fi

PORT=$(echo "$LISTENER" | jq -r '.port')
PROTOCOL=$(echo "$LISTENER" | jq -r '.protocol')
HOSTNAME=$(echo "$LISTENER" | jq -r '.hostname // empty')
if [[ "$PORT" != "80" || "$PROTOCOL" != "HTTP" || "$HOSTNAME" != "shop.helioscale.io" ]]; then
    echo "❌ Listener 'web' is $PROTOCOL:$PORT for '${HOSTNAME:-<any>}', expected HTTP:80 for 'shop.helioscale.io'"
    exit 1
fi

ACCEPTED=""
for _ in $(seq 1 12); do
    ACCEPTED=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
    if [[ "$ACCEPTED" == "True" ]]; then
        break
    fi
    sleep 5
done

if [[ "$ACCEPTED" != "True" ]]; then
    echo "❌ '$GATEWAY' reports Accepted='${ACCEPTED:-<none>}'"
    exit 1
fi

echo "✅ Gateway '$GATEWAY' serves HTTP:80 for 'shop.helioscale.io' and was accepted"
exit 0
