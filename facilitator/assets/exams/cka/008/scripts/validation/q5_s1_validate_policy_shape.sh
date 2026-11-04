#!/bin/bash

set -e

# The DNS allowance is graded structurally here as well as by a live lookup in
# s2, because both protocols matter: UDP 53 carries almost every query, but a
# resolver falls back to TCP for large responses, and a UDP-only policy fails
# intermittently and confusingly rather than outright.

NAMESPACE="np-egress"
POLICY="orders-egress"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

SELECTOR=$(echo "$SPEC" | jq -r '.spec.podSelector.matchLabels.app // empty')
if [[ "$SELECTOR" != "orders" ]]; then
    echo "❌ '$POLICY' selects '${SELECTOR:-<everything>}', expected the Pods labelled app=orders"
    exit 1
fi

TYPES=$(echo "$SPEC" | jq -r '[.spec.policyTypes[]? | select(. == "Egress")] | length')
if [[ "$TYPES" != "1" ]]; then
    echo "❌ '$POLICY' does not declare the 'Egress' policy type"
    exit 1
fi

DNS_UDP=$(echo "$SPEC" | jq '[.spec.egress[]?.ports[]? | select(.port == 53 and (.protocol // "TCP") == "UDP")] | length')
if [[ "$DNS_UDP" == "0" ]]; then
    echo "❌ '$POLICY' does not permit egress to port 53 over UDP"
    exit 1
fi

DNS_TCP=$(echo "$SPEC" | jq '[.spec.egress[]?.ports[]? | select(.port == 53 and (.protocol // "TCP") == "TCP")] | length')
if [[ "$DNS_TCP" == "0" ]]; then
    echo "❌ '$POLICY' does not permit egress to port 53 over TCP"
    exit 1
fi

OPEN=$(echo "$SPEC" | jq '[.spec.egress[]? | select(((.to // []) | length) == 0 and ((.ports // []) | length) == 0)] | length')
if [[ "$OPEN" != "0" ]]; then
    echo "❌ '$POLICY' contains a rule that permits all egress traffic"
    exit 1
fi

echo "✅ '$POLICY' restricts egress from the app=orders Pods and allows DNS over UDP and TCP"
exit 0
