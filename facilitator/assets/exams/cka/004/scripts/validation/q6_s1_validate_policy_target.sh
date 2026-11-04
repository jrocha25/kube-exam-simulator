#!/bin/bash
set -e

NAMESPACE="ledger"
POLICY="ledger-ingress"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

SELECTOR=$(echo "$SPEC" | jq -r '.spec.podSelector.matchLabels.app // empty')
if [[ "$SELECTOR" != "ledger" ]]; then
    echo "❌ NetworkPolicy '$POLICY' must select the Pods labelled 'app=ledger' (got: 'app=${SELECTOR:-<none>}')"
    exit 1
fi

POLICY_TYPES=$(echo "$SPEC" | jq -r '[.spec.policyTypes // [] | .[]] | sort | join(",")')
if [[ "$POLICY_TYPES" != "Ingress" ]]; then
    echo "❌ NetworkPolicy '$POLICY' must declare exactly the policy type 'Ingress' (got: '${POLICY_TYPES:-<none>}')"
    exit 1
fi

echo "✅ NetworkPolicy '$POLICY' restricts ingress for the Pods labelled 'app=ledger'"
exit 0
