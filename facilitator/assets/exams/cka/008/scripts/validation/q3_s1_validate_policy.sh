#!/bin/bash

set -e

NAMESPACE="np-crossns"
POLICY="payments-ingress"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

SELECTOR=$(echo "$SPEC" | jq -r '.spec.podSelector.matchLabels.app // empty')
if [[ "$SELECTOR" != "payments" ]]; then
    echo "❌ '$POLICY' selects '${SELECTOR:-<everything>}', expected the Pods labelled app=payments"
    exit 1
fi

TYPES=$(echo "$SPEC" | jq -r '[.spec.policyTypes[]? | select(. == "Ingress")] | length')
if [[ "$TYPES" != "1" ]]; then
    echo "❌ '$POLICY' does not declare the 'Ingress' policy type"
    exit 1
fi

echo "✅ '$POLICY' applies Ingress rules to the app=payments Pods"
exit 0
