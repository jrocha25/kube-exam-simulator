#!/bin/bash

set -e

# Swapping the affinity rule for a nodeSelector, or quietly dropping to fewer
# replicas, both make the Pending symptom go away without solving the stated
# problem. The question forbids each of them.

NAMESPACE="ts-sched"
DEPLOYMENT="customs-broker"
REPLICAS="3"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json)

DECLARED=$(echo "$SPEC" | jq -r '.spec.replicas')
if [[ "$DECLARED" != "$REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' declares ${DECLARED} replicas, expected $REPLICAS"
    exit 1
fi

if [[ "$(echo "$SPEC" | jq '.spec.template.spec.nodeSelector // {} | length')" != "0" ]]; then
    echo "❌ '$DEPLOYMENT' now uses a nodeSelector; the placement must stay expressed as node affinity"
    exit 1
fi

TERMS=$(echo "$SPEC" | jq '
    .spec.template.spec.affinity.nodeAffinity
    .requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms // [] | length')
if [[ "$TERMS" -lt 1 ]]; then
    echo "❌ '$DEPLOYMENT' no longer declares required node affinity; removing it is not the fix"
    exit 1
fi

VALUES=$(echo "$SPEC" | jq -r '
    [ .spec.template.spec.affinity.nodeAffinity
      .requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?.matchExpressions[]?
      | select(.key == "node-class") | (.values // [])[] ] | unique | join(" ")')

if [[ -z "$VALUES" ]]; then
    echo "❌ The node affinity no longer constrains 'node-class'"
    exit 1
fi

for VALUE in $VALUES; do
    if [[ "$VALUE" != "compute" && "$VALUE" != "memory" ]]; then
        echo "❌ The node affinity still admits node-class '$VALUE', which is not an approved class"
        exit 1
    fi
done

echo "✅ '$DEPLOYMENT' still declares $REPLICAS replicas and still selects nodes by affinity on approved classes"
exit 0
