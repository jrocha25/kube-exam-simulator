#!/bin/bash
set -e

NAMESPACE="ledger"
POLICY="ledger-ingress"
CLIENT_NAMESPACE="ledger-clients"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

RULES=$(echo "$SPEC" | jq '.spec.ingress // [] | length')
if [[ "$RULES" != "1" ]]; then
    echo "❌ NetworkPolicy '$POLICY' must declare exactly one ingress rule (found $RULES)"
    exit 1
fi

PEERS=$(echo "$SPEC" | jq '.spec.ingress[0].from // [] | length')
if [[ "$PEERS" != "1" ]]; then
    echo "❌ The ingress rule must allow exactly one peer (found $PEERS). Traffic is not restricted to '$CLIENT_NAMESPACE'"
    exit 1
fi

PEER_KEYS=$(echo "$SPEC" | jq -r '[.spec.ingress[0].from[0] | keys[]] | sort | join(",")')
if [[ "$PEER_KEYS" != "namespaceSelector" ]]; then
    echo "❌ The peer must be selected by a namespaceSelector only (found: '$PEER_KEYS')"
    exit 1
fi

PEER_NS=$(echo "$SPEC" | jq -r '.spec.ingress[0].from[0].namespaceSelector.matchLabels["kubernetes.io/metadata.name"] // empty')
if [[ "$PEER_NS" != "$CLIENT_NAMESPACE" ]]; then
    echo "❌ The namespaceSelector must match only '$CLIENT_NAMESPACE' (got: '${PEER_NS:-any namespace}')"
    exit 1
fi

PORTS=$(echo "$SPEC" | jq '.spec.ingress[0].ports // [] | length')
if [[ "$PORTS" != "1" ]]; then
    echo "❌ The ingress rule must allow exactly one port (found $PORTS)"
    exit 1
fi

PORT=$(echo "$SPEC" | jq -r '.spec.ingress[0].ports[0].port // empty')
PROTOCOL=$(echo "$SPEC" | jq -r '.spec.ingress[0].ports[0].protocol // "TCP"')
if [[ "$PORT" != "80" ]] || [[ "$PROTOCOL" != "TCP" ]]; then
    echo "❌ The ingress rule must allow TCP port 80 (got: '$PROTOCOL/$PORT')"
    exit 1
fi

echo "✅ The applied NetworkPolicy is the least permissive candidate"
exit 0
