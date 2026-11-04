#!/bin/bash

set -e

# A pure constraint check: it passes on an untouched cluster, which is why it
# carries a single mark. The point of the question is what gets added, not what
# survives.

NAMESPACE="np-additive"
POLICY="allow-frontend"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' has been deleted from '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

SELECTOR=$(echo "$SPEC" | jq -r '.spec.podSelector.matchLabels.app // empty')
if [[ "$SELECTOR" != "reports" ]]; then
    echo "❌ '$POLICY' no longer selects the Pods labelled app=reports"
    exit 1
fi

RULES=$(echo "$SPEC" | jq '[.spec.ingress[]?] | length')
if [[ "$RULES" != "1" ]]; then
    echo "❌ '$POLICY' now has $RULES ingress rule(s); it must be left exactly as it was"
    exit 1
fi

PEERS=$(echo "$SPEC" | jq -r '[.spec.ingress[0].from[]?] | length')
FROM_ROLE=$(echo "$SPEC" | jq -r '.spec.ingress[0].from[0].podSelector.matchLabels.role // empty')
PORTS=$(echo "$SPEC" | jq -r '[.spec.ingress[0].ports[]? | select(.port == 80 and (.protocol // "TCP") == "TCP")] | length')
if [[ "$PEERS" != "1" || "$FROM_ROLE" != "frontend" || "$PORTS" != "1" ]]; then
    echo "❌ '$POLICY' has been modified; it must still allow only role=frontend on TCP 80"
    exit 1
fi

echo "✅ '$POLICY' is unchanged"
exit 0
