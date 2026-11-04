#!/bin/bash
set -e

NAMESPACE="net-radar"
POLICY="radar-egress"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicies are not enforced on this cluster, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

if ! jq -e '.spec.policyTypes | index("Egress")' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' does not declare the Egress policy type"
    exit 1
fi
if jq -e '.spec.policyTypes | index("Ingress")' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' also restricts Ingress; the question asks for Egress only"
    exit 1
fi
if ! jq -e '.spec.podSelector.matchLabels.app == "radar"' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' does not select the Pods labelled app=radar"
    exit 1
fi
if ! jq -e '(.spec.egress // []) | length > 0' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' has no egress rules at all, which denies everything"
    exit 1
fi

# A rule with no "to" permits every destination, which would make the two deny
# checks unsatisfiable no matter what else the policy says.
if jq -e '.spec.egress[] | select((.to // []) | length == 0)' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' contains a rule with no destination, which permits all outgoing traffic"
    exit 1
fi
if jq -e '.spec.egress[].to[]?.ipBlock?.cidr | select(. == "0.0.0.0/0")' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' permits the whole 0.0.0.0/0 range"
    exit 1
fi

echo "✅ '$POLICY' restricts egress from app=radar and has no blanket allow rule"
exit 0
