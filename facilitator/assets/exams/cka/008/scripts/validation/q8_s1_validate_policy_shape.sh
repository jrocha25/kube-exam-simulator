#!/bin/bash

set -e

# The question asks for the two-value client set to be expressed with a single
# matchExpressions 'In' rule rather than two matchLabels peers. Both would carry
# the same traffic, so this is the one part of the answer that traffic cannot
# grade and the spec has to.

NAMESPACE="np-ports"
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

HTTP_RULE=$(echo "$SPEC" | jq '
    [ .spec.ingress[]?
      | select(([.ports[]? | select(.port == 80 and (.protocol // "TCP") == "TCP")] | length) == 1)
      | select(
          [ .from[]?.podSelector.matchExpressions[]?
            | select(.key == "role" and .operator == "In")
            | select(([.values[]? | select(. == "frontend")] | length) == 1)
            | select(([.values[]? | select(. == "monitoring")] | length) == 1)
            | select(([.values[]?] | length) == 2)
          ] | length == 1
        )
    ] | length')

if [[ "$HTTP_RULE" != "1" ]]; then
    echo "❌ '$POLICY' has no TCP 80 rule whose peer is a matchExpressions 'In' rule over role=[frontend,monitoring]"
    exit 1
fi

METRICS_RULE=$(echo "$SPEC" | jq '
    [ .spec.ingress[]?
      | select(([.ports[]? | select(.port == 9090 and (.protocol // "TCP") == "TCP")] | length) == 1)
    ] | length')

if [[ "$METRICS_RULE" != "1" ]]; then
    echo "❌ '$POLICY' has no rule permitting TCP 9090"
    exit 1
fi

echo "✅ '$POLICY' allows role In [frontend,monitoring] on TCP 80 and has a separate TCP 9090 rule"
exit 0
