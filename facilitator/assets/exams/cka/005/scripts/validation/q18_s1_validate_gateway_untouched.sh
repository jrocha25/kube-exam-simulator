#!/bin/bash
set -e

NAMESPACE="edge-stuck"
GATEWAY="edge-gw"

if ! kubectl get gateway "$GATEWAY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' no longer exists in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o json)

COUNT=$(echo "$SPEC" | jq -r '.spec.listeners | length')
if [[ "$COUNT" != "1" ]]; then
    echo "❌ '$GATEWAY' now has $COUNT listeners; it belongs to the platform team and must not be changed"
    exit 1
fi

LISTENER=$(echo "$SPEC" | jq -r '.spec.listeners[0]')
NAME=$(echo "$LISTENER" | jq -r '.name')
PORT=$(echo "$LISTENER" | jq -r '.port')
HOSTNAME=$(echo "$LISTENER" | jq -r '.hostname // empty')
FROM=$(echo "$LISTENER" | jq -r '.allowedRoutes.namespaces.from // "Same"')

if [[ "$NAME" != "public" || "$PORT" != "80" || "$HOSTNAME" != "catalog.helioscale.io" || "$FROM" != "Same" ]]; then
    echo "❌ '$GATEWAY' was modified: listener '$NAME' on port '$PORT' for '${HOSTNAME:-<any>}' allowing routes from '$FROM'"
    exit 1
fi

echo "✅ Gateway '$GATEWAY' is unchanged"
exit 0
