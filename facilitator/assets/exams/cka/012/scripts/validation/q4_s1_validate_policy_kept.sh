#!/bin/bash
set -e

# A constraint check, and true on the seeded state, which is why it is worth one
# mark: the question is not "make a policy exist", it is "narrow the one that is
# already there". Deleting it and starting again under the same name is fine --
# the name and the target are what the question pins down.

NAMESPACE="net-array"
POLICY="array-ingress"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicies are not enforced on this cluster, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ NetworkPolicy '$POLICY' no longer exists in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

if ! jq -e --arg l "station-relay" '
    (.spec.podSelector.matchLabels.app == $l)
    or ([.spec.podSelector.matchExpressions[]? | select(.key == "app") | select((.values // []) | index($l))] | length > 0)
  ' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' no longer selects the Pods labelled app=station-relay"
    exit 1
fi
if ! jq -e '.spec.policyTypes | index("Ingress")' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' no longer declares the Ingress policy type"
    exit 1
fi

echo "✅ '$POLICY' still exists and still selects app=station-relay"
exit 0
