#!/bin/bash

set -e

# One nodeSelectorTerm carrying BOTH expressions is the graded idea. Separate
# terms are OR-ed, so splitting them would match every node that is either the
# right class or not decommissioning -- which is almost all of them.
#
# nodeSelector is rejected outright: it can express the "In" half and cannot
# express the negative half at all, so allowing it would let a wrong answer look
# right on the class check.

NAMESPACE="sched-nodeaff"
DEPLOYMENT="sorting-engine"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json)

if [[ "$(echo "$SPEC" | jq '.spec.template.spec.nodeSelector // {} | length')" != "0" ]]; then
    echo "❌ '$DEPLOYMENT' uses a nodeSelector; this must be expressed as node affinity"
    exit 1
fi

TERMS=$(echo "$SPEC" | jq '
    .spec.template.spec.affinity.nodeAffinity
    .requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms // [] | length')
if [[ "$TERMS" != "1" ]]; then
    echo "❌ Expected exactly 1 nodeSelectorTerm under requiredDuringSchedulingIgnoredDuringExecution, found ${TERMS}"
    echo "   Separate terms are OR-ed; both conditions belong in one term."
    exit 1
fi

CLASS_OK=$(echo "$SPEC" | jq '
    [ .spec.template.spec.affinity.nodeAffinity
      .requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[]?
      | select(.key == "node-class" and .operator == "In")
      | select((.values | sort) == ["compute","memory"])
    ] | length')
if [[ "$CLASS_OK" != "1" ]]; then
    echo "❌ No matchExpression selecting node-class In [compute, memory]"
    exit 1
fi

EXCLUDE_OK=$(echo "$SPEC" | jq '
    [ .spec.template.spec.affinity.nodeAffinity
      .requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[]?
      | select(.key == "decommission")
      | select(.operator == "DoesNotExist" or (.operator == "NotIn" and ((.values // []) | index("pending"))))
    ] | length')
if [[ "$EXCLUDE_OK" -lt 1 ]]; then
    echo "❌ The term does not exclude nodes flagged for decommission"
    echo "   Expected a 'decommission' expression using DoesNotExist, or NotIn [pending]."
    exit 1
fi

echo "✅ '$DEPLOYMENT' requires node-class In [compute, memory] and excludes decommissioning nodes in one term"
exit 0
