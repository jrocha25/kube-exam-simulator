#!/bin/bash
set -e

# A constraint check: apron-egress is the platform team's and has to survive the
# repair. This passes on the seeded, broken state by design, which is why it is
# worth one mark -- the marks for this question are on the two deny checks.

NAMESPACE="net-apron"
POLICY="apron-egress"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicies are not enforced on this cluster, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ NetworkPolicy '$POLICY' was deleted; the question asks for it to be kept"
    exit 1
fi

JSON=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

if ! jq -e '.spec.policyTypes | index("Egress")' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' no longer declares the Egress policy type"
    exit 1
fi
if ! jq -e '.spec.podSelector.matchLabels.app == "apron"' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' no longer selects the Pods labelled app=apron"
    exit 1
fi
if jq -e '.spec.egress[] | select((.to // []) | length == 0)' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' now contains a rule with no destination, which permits all outgoing traffic"
    exit 1
fi
if jq -e '.spec.egress[].to[]?.ipBlock?.cidr | select(. == "0.0.0.0/0")' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' now permits the whole 0.0.0.0/0 range"
    exit 1
fi

echo "✅ '$POLICY' still exists and still restricts egress from app=apron"
exit 0
