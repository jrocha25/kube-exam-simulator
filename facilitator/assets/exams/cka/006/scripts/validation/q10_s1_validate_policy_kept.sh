#!/bin/bash
set -e

NAMESPACE="net-billing"
POLICY="billing-egress"

JSON=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ NetworkPolicy '$POLICY' was deleted. It had to be kept and repaired."
    exit 1
fi

TARGET=$(echo "$JSON" | jq -r '.spec.podSelector.matchLabels.app // empty')
if [[ "$TARGET" != "billing" ]]; then
    echo "❌ '$POLICY' now selects app='${TARGET:-<everything>}', expected 'billing'"
    exit 1
fi

TYPES=$(echo "$JSON" | jq -r '[.spec.policyTypes[]] | join(",")')
if [[ "$TYPES" != *Egress* ]]; then
    echo "❌ '$POLICY' no longer declares the Egress policy type"
    exit 1
fi

# An empty 'to' with no ports, or a 0.0.0.0/0 block, re-opens everything and
# defeats the restriction the question said must stay in force.
OPEN=$(echo "$JSON" | jq '[.spec.egress[]? | select((.to // []) == [] and (.ports // []) == [])] | length')
if [[ "${OPEN:-0}" -gt 0 ]]; then
    echo "❌ '$POLICY' now contains a rule that permits all egress traffic"
    exit 1
fi

WIDE=$(echo "$JSON" | jq '[.spec.egress[]?.to[]? | select(.ipBlock.cidr == "0.0.0.0/0")] | length')
if [[ "${WIDE:-0}" -gt 0 ]]; then
    echo "❌ '$POLICY' now permits egress to 0.0.0.0/0"
    exit 1
fi

echo "✅ '$POLICY' still exists and still restricts the billing Pod's egress"
exit 0
