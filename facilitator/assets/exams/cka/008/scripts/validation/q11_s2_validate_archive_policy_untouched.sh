#!/bin/bash

set -e

# Constraint check, worth a single mark because it passes on an untouched
# cluster. It exists to catch the wrong diagnosis: the archive side looks like
# the obvious suspect and is already correct.

STORE_NS="np-ts-egress-store"
CLIENT_NS="np-ts-egress"
POLICY="archive-ingress"

if ! kubectl get networkpolicy "$POLICY" -n "$STORE_NS" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' has been deleted from '$STORE_NS'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$STORE_NS" -o json)

SELECTOR=$(echo "$SPEC" | jq -r '.spec.podSelector.matchLabels.app // empty')
RULES=$(echo "$SPEC" | jq '[.spec.ingress[]?] | length')
PEER_NS=$(echo "$SPEC" | jq -r '.spec.ingress[0].from[0].namespaceSelector.matchLabels["kubernetes.io/metadata.name"] // empty')
PORTS=$(echo "$SPEC" | jq '[.spec.ingress[0].ports[]? | select(.port == 80 and (.protocol // "TCP") == "TCP")] | length')

if [[ "$SELECTOR" != "archive" || "$RULES" != "1" || "$PEER_NS" != "$CLIENT_NS" || "$PORTS" != "1" ]]; then
    echo "❌ '$POLICY' has been modified; it belongs to another team and must be left alone"
    exit 1
fi

ARCHIVE_IMAGE=$(kubectl get pod archive -n "$STORE_NS" -o jsonpath='{.spec.containers[0].image}' 2> /dev/null || true)
if [[ "$ARCHIVE_IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ Pod 'archive' has been changed; the archive workload must be left alone"
    exit 1
fi

echo "✅ '$POLICY' and the 'archive' workload are unchanged"
exit 0
