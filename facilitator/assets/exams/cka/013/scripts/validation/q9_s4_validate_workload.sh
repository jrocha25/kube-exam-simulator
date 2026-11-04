#!/bin/bash
set -e

NAMESPACE="wl-quorum"
DEPLOYMENT="quorum"
NODE02=$(grep '^node02=' /tmp/exam/nodes.env | cut -d= -f2)

# Three ready replicas off node02 is the starting state too, if setup happened
# to place none there; it only means something once node02 is out of service.
if [[ "$(kubectl get node "$NODE02" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)" != "true" ]]; then
    echo "❌ node02 is not cordoned"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    ON_NODE02=$(kubectl get pods -n "$NAMESPACE" -l app=quorum --field-selector "spec.nodeName=${NODE02}" -o name 2>/dev/null | wc -l)
    [[ "$READY" == "3" && "$ON_NODE02" == "0" ]] && break
    sleep 5
done
if [[ "$READY" != "3" || "$ON_NODE02" != "0" ]]; then
    echo "❌ $DEPLOYMENT has ${READY:-0} ready replicas and $ON_NODE02 Pod(s) on node02"
    exit 1
fi

echo "✅ $DEPLOYMENT has 3 ready replicas, none on node02"
exit 0
