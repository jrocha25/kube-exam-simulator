#!/bin/bash

set -e

# The rule has to select the OTHER workload. A self-selecting anti-affinity --
# the shape of the documentation's example -- spreads the batch pods across nodes
# and is still free to land one on the protected node, so the selector is checked
# here and the consequence is checked by the placement step.

NAMESPACE="sched-antiaff"
DEPLOYMENT="label-printer"
PROTECTED="scan-gateway"
TOPOLOGY_KEY="kubernetes.io/hostname"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json)

TERMS=$(echo "$SPEC" | jq '
    .spec.template.spec.affinity.podAntiAffinity
    .requiredDuringSchedulingIgnoredDuringExecution // [] | length')
if [[ "$TERMS" -lt 1 ]]; then
    echo "❌ '$DEPLOYMENT' has no requiredDuringSchedulingIgnoredDuringExecution pod anti-affinity"
    echo "   A preference would let a replica share the node anyway."
    exit 1
fi

KEY_OK=$(echo "$SPEC" | jq --arg k "$TOPOLOGY_KEY" '
    [ .spec.template.spec.affinity.podAntiAffinity
      .requiredDuringSchedulingIgnoredDuringExecution[]?
      | select(.topologyKey == $k) ] | length')
if [[ "$KEY_OK" -lt 1 ]]; then
    echo "❌ No anti-affinity term uses topologyKey '$TOPOLOGY_KEY'"
    exit 1
fi

# Every label value the rule mentions, from matchLabels and matchExpressions alike.
VALUES=$(echo "$SPEC" | jq -r '
    [ .spec.template.spec.affinity.podAntiAffinity
      .requiredDuringSchedulingIgnoredDuringExecution[]?.labelSelector
      | ((.matchLabels // {}) | to_entries[] | .value),
        ((.matchExpressions // [])[] | (.values // [])[])
    ] | unique | join(" ")')

if [[ " $VALUES " != *" $PROTECTED "* ]]; then
    echo "❌ The anti-affinity selector does not mention '$PROTECTED' (it selects: ${VALUES:-nothing})"
    echo "   The rule must select the protected workload, not this one."
    exit 1
fi

if [[ " $VALUES " == *" $DEPLOYMENT "* ]]; then
    echo "❌ The anti-affinity selector also selects '$DEPLOYMENT' itself"
    echo "   The requirement is to stay off the protected workload's node, not to spread this one."
    exit 1
fi

echo "✅ '$DEPLOYMENT' requires anti-affinity to '$PROTECTED' on '$TOPOLOGY_KEY'"
exit 0
