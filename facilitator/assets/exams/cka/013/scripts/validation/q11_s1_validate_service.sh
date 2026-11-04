#!/bin/bash
set -e

NAMESPACE="net-vault"
SERVICE="vault-proxy"

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Service '$SERVICE' not found in '$NAMESPACE'"
    exit 1
fi

if [[ "$(echo "$JSON" | jq '.spec.selector // {} | length')" != "0" ]]; then
    echo "❌ '$SERVICE' has a selector"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -r '.spec.type')" != "ClusterIP" ]]; then
    echo "❌ '$SERVICE' is not a ClusterIP Service"
    exit 1
fi

PORTS=$(echo "$JSON" | jq -c '[.spec.ports[] | {name, port, targetPort, protocol}] | sort_by(.name)')
WANT='[{"name":"api","port":80,"targetPort":8080,"protocol":"TCP"},{"name":"metrics","port":9100,"targetPort":9100,"protocol":"TCP"}]'
if [[ "$PORTS" != "$WANT" ]]; then
    echo "❌ '$SERVICE' ports are $PORTS"
    echo "   expected $WANT"
    exit 1
fi

echo "✅ '$SERVICE' has no selector and the ports api 80→8080 and metrics 9100"
exit 0
