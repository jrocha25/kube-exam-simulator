#!/bin/bash

set -e

NAMESPACE="np-external"
POLICY="gateway-egress"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

SELECTOR=$(echo "$SPEC" | jq -r '.spec.podSelector.matchLabels.app // empty')
if [[ "$SELECTOR" != "gateway" ]]; then
    echo "❌ '$POLICY' selects '${SELECTOR:-<everything>}', expected the Pods labelled app=gateway"
    exit 1
fi

TYPES=$(echo "$SPEC" | jq -r '[.spec.policyTypes[]?] | sort | join(",")')
if [[ "$TYPES" != "Egress" ]]; then
    echo "❌ '$POLICY' declares policyTypes '${TYPES:-<none>}', expected exactly 'Egress'"
    exit 1
fi

echo "✅ '$POLICY' applies Egress rules to the app=gateway Pods"
exit 0
