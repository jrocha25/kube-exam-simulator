#!/bin/bash

set -e

# The check that tells a correct answer from a docs-shaped one. Resolved live:
# whichever node the protected workload is on, no batch replica may be there.

NAMESPACE="sched-antiaff"
DEPLOYMENT="label-printer"
PROTECTED="scan-gateway"

if [[ -f /tmp/exam/insufficient-nodes ]]; then
    echo "❌ This cluster has fewer than 3 schedulable nodes, so placement cannot be graded"
    echo "   See the shared setup warnings in the exam logs."
    exit 1
fi

PROTECTED_NODE=$(kubectl get pods -n "$NAMESPACE" -l app="$PROTECTED" \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].spec.nodeName}' 2> /dev/null || true)
if [[ -z "$PROTECTED_NODE" ]]; then
    echo "❌ No running '$PROTECTED' Pod found; the question environment is incomplete"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
if [[ "$READY" != "2" ]]; then
    echo "❌ '$DEPLOYMENT' is not fully ready (${READY:-0}/2), so its placement proves nothing yet"
    exit 1
fi

NODES=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}')
if [[ -z "$NODES" ]]; then
    echo "❌ No running Pods found for '$DEPLOYMENT' (are they labelled app=$DEPLOYMENT?)"
    exit 1
fi

while read -r NODE; do
    [[ -z "$NODE" ]] && continue
    if [[ "$NODE" == "$PROTECTED_NODE" ]]; then
        echo "❌ A '$DEPLOYMENT' Pod is running on '$NODE', the same node as '$PROTECTED'"
        exit 1
    fi
done <<< "$NODES"

echo "✅ No '$DEPLOYMENT' replica shares node '$PROTECTED_NODE' with '$PROTECTED'"
exit 0
