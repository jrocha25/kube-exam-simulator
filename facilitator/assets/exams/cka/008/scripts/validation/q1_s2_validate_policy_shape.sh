#!/bin/bash

set -e

# A default-deny is defined by what it does *not* contain: an empty podSelector
# so it catches every Pod, Ingress in policyTypes so ingress becomes isolated,
# and no ingress rules at all so nothing is let back in.

NAMESPACE="np-baseline"
POLICY="default-deny-ingress"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

SELECTOR_KEYS=$(echo "$SPEC" | jq -r '(.spec.podSelector // {}) | keys | length')
if [[ "$SELECTOR_KEYS" != "0" ]]; then
    echo "❌ '$POLICY' has a podSelector, so it does not apply to every Pod in the namespace"
    exit 1
fi

TYPES=$(echo "$SPEC" | jq -r '[.spec.policyTypes[]?] | sort | join(",")')
if [[ "$TYPES" != "Ingress" ]]; then
    echo "❌ '$POLICY' declares policyTypes '${TYPES:-<none>}', expected exactly 'Ingress'"
    exit 1
fi

RULES=$(echo "$SPEC" | jq -r '[.spec.ingress[]?] | length')
if [[ "$RULES" != "0" ]]; then
    echo "❌ '$POLICY' has $RULES ingress rule(s), so it permits traffic instead of denying it"
    exit 1
fi

echo "✅ '$POLICY' denies all ingress to every Pod in '$NAMESPACE'"
exit 0
