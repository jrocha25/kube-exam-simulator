#!/bin/bash
set -e

# The shape check, and it has real work to do. Three wrong answers reach the
# right traffic outcome and are not the graded idea:
#
#   * a deny-all policy (no ingress rules) passes every "cannot reach" probe
#   * an ipBlock naming the allowed client's /32 passes them too
#   * the documentation's own AND block, pasted with the names changed, has no
#     ports and no second rule
#
# So this asserts the structure the question asks for: one rule for 8443 whose
# "from" has exactly ONE entry carrying both selectors -- which is the whole
# AND-versus-OR lesson -- and a separate rule for 9100.

NAMESPACE="net-tremor"
POLICY="tremor-ingress"

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

if ! jq -e --arg l "tremor-ingest" '
    (.spec.podSelector.matchLabels.app == $l)
    or ([.spec.podSelector.matchExpressions[]? | select(.key == "app") | select((.values // []) | index($l))] | length > 0)
  ' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' does not select the Pods labelled app=tremor-ingest"
    exit 1
fi
if ! jq -e '.spec.policyTypes | index("Ingress")' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' does not declare the Ingress policy type"
    exit 1
fi
if jq -e '.spec.policyTypes | index("Egress")' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' also restricts Egress; the question asks for ingress only"
    exit 1
fi
if ! jq -e '(.spec.ingress // []) | length > 0' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' has no ingress rules at all, which denies everything"
    exit 1
fi

# A rule with no "from" admits every source, which would make the deny checks
# unsatisfiable whatever else the policy says.
if jq -e '.spec.ingress[] | select((.from // []) | length == 0)' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' has a rule with no 'from', which admits every source"
    exit 1
fi
if jq -e '[.spec.ingress[]?.from[]? | select(has("ipBlock"))] | length > 0' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' identifies a source by ipBlock; the question is about selecting Pods and namespaces"
    exit 1
fi

# The 8443 rule: exactly one "from" entry, carrying both selectors, and the
# namespace selected with a matchExpressions term as the question asks.
if ! jq -e '
  [ .spec.ingress[]
    | select((.ports // []) | any((.port == 8443) and ((.protocol // "TCP") == "TCP")))
    | select((.from | length) == 1)
    | select((.from[0].namespaceSelector // {}) != {})
    | select((.from[0].podSelector // {}) != {})
    | select([ .from[0].namespaceSelector.matchExpressions[]? | select(.key == "seismo.io/tier") ] | length > 0)
  ] | length > 0' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' has no rule for TCP 8443 whose single 'from' entry carries both a namespaceSelector"
    echo "   (a matchExpressions term on seismo.io/tier) and a podSelector for station-role=gateway."
    echo "   Two separate 'from' entries are an OR and admit either condition on its own."
    exit 1
fi

if ! jq -e '
  [ .spec.ingress[]
    | select((.ports // []) | any((.port == 9100) and ((.protocol // "TCP") == "TCP")))
  ] | length > 0' <<<"$JSON" >/dev/null; then
    echo "❌ '$POLICY' has no rule for TCP 9100"
    exit 1
fi

echo "✅ '$POLICY' restricts ingress to app=tremor-ingest with one AND rule for 8443 and a separate rule for 9100"
exit 0
