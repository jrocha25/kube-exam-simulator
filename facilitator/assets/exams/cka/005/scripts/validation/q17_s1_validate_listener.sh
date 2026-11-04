#!/bin/bash
set -e

NAMESPACE="edge-platform"
GATEWAY="platform-gw"

if ! kubectl get gateway "$GATEWAY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' not found in namespace '$NAMESPACE'"
    exit 1
fi

LISTENER=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o json \
    | jq -r '[.spec.listeners[]? | select(.name=="web")][0] // empty')
if [[ -z "$LISTENER" ]]; then
    echo "❌ '$GATEWAY' has no listener named 'web'"
    exit 1
fi

HOSTNAME=$(echo "$LISTENER" | jq -r '.hostname // empty')
PORT=$(echo "$LISTENER" | jq -r '.port')
if [[ "$HOSTNAME" != "*.helioscale.io" || "$PORT" != "80" ]]; then
    echo "❌ Listener 'web' was changed: it serves '${HOSTNAME:-<any>}' on port '$PORT'"
    exit 1
fi

FROM=$(echo "$LISTENER" | jq -r '.allowedRoutes.namespaces.from // empty')
if [[ "$FROM" != "Selector" ]]; then
    echo "❌ Listener 'web' accepts routes from '${FROM:-Same}', expected 'Selector'"
    exit 1
fi

MATCH=$(echo "$LISTENER" | jq -r '.allowedRoutes.namespaces.selector.matchLabels["gateway-access"] // empty')
if [[ "$MATCH" != "allowed" ]]; then
    echo "❌ Listener 'web' selects namespaces on 'gateway-access=${MATCH:-<none>}', expected 'allowed'"
    exit 1
fi

echo "✅ Listener 'web' accepts routes from namespaces labelled gateway-access=allowed"
exit 0
