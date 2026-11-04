#!/bin/bash
set -e

NAMESPACE="net-orders"
POLICY="orders-lockdown"

JSON=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

TARGET=$(echo "$JSON" | jq -r '.spec.podSelector.matchLabels.app // empty')
if [[ "$TARGET" != "orders" ]]; then
    echo "❌ '$POLICY' selects app='${TARGET:-<everything>}', expected the 'orders' Pod"
    exit 1
fi

TYPES=$(echo "$JSON" | jq -r '[.spec.policyTypes[]] | sort | join(",")')
if [[ "$TYPES" != "Egress,Ingress" ]]; then
    echo "❌ '$POLICY' declares policyTypes '$TYPES', expected both Ingress and Egress"
    exit 1
fi

echo "✅ '$POLICY' applies to the orders Pod and declares both policy types"
exit 0
