#!/bin/bash

set -e

# The eligible set is exactly one node, so placement is unambiguous. This is the
# check a single-expression answer fails: it also matches the memory node, which
# is flagged for decommission.
#
# The eligible node is resolved live rather than hardcoded, so the check survives
# a change of node names or of which agent got which class.

NAMESPACE="sched-nodeaff"
DEPLOYMENT="sorting-engine"
REPLICAS="2"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

ELIGIBLE=$(kubectl get nodes -o json | jq -r '
    [ .items[]
      | select((.metadata.labels["node-class"] // "") as $c | $c == "compute" or $c == "memory")
      | select(.metadata.labels | has("decommission") | not)
      | .metadata.name ] | join(" ")')

if [[ -z "$ELIGIBLE" ]]; then
    echo "❌ No node matches node-class In [compute, memory] without a decommission label"
    echo "   The shared setup script labels the nodes; check its output in the exam logs."
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
    [[ "$READY" == "$REPLICAS" ]] && break
    sleep 5
done

if [[ "$READY" != "$REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' has ${READY:-0}/${REPLICAS} ready replicas"
    exit 1
fi

NODES=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u)

if [[ -z "$NODES" ]]; then
    echo "❌ No running Pods found for '$DEPLOYMENT' (are they labelled app=$DEPLOYMENT?)"
    exit 1
fi

while read -r NODE; do
    [[ -z "$NODE" ]] && continue
    if [[ " $ELIGIBLE " != *" $NODE "* ]]; then
        echo "❌ A Pod is running on '$NODE', which is not eligible (eligible: $ELIGIBLE)"
        exit 1
    fi
done <<< "$NODES"

echo "✅ All $REPLICAS replicas are running, and only on eligible nodes ($ELIGIBLE)"
exit 0
