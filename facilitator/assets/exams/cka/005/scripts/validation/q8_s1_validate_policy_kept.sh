#!/bin/bash
set -e

NAMESPACE="net-egress"
POLICY="frontend-egress"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' no longer exists in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

SELECTOR=$(echo "$SPEC" | jq -r '.spec.podSelector.matchLabels.app // empty')
if [[ "$SELECTOR" != "frontend" ]]; then
    echo "❌ '$POLICY' selects '${SELECTOR:-<everything>}', expected the Pods labelled app=frontend"
    exit 1
fi

EGRESS=$(echo "$SPEC" | jq -r '[.spec.policyTypes[]? | select(. == "Egress")] | length')
if [[ "$EGRESS" != "1" ]]; then
    echo "❌ '$POLICY' no longer declares the 'Egress' policy type"
    exit 1
fi

# A rule with neither a destination nor a port permits everything, which would
# make the restriction meaningless.
OPEN=$(echo "$SPEC" | jq -r '[.spec.egress[]? | select(((.to // []) | length) == 0 and ((.ports // []) | length) == 0)] | length')
if [[ "$OPEN" != "0" ]]; then
    echo "❌ '$POLICY' contains a rule that permits all egress traffic"
    exit 1
fi

echo "✅ '$POLICY' is still in force and still restricts egress"
exit 0
