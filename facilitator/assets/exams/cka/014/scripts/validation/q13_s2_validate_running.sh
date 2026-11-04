#!/bin/bash
set -e

NAMESPACE="crane-sim"
DEPLOYMENT="crane-sim"

NODE02=$(grep '^node02=' /tmp/exam/nodes.env | cut -d= -f2)

if [[ "$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)" != "3" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' is not scaled to 3 replicas"
    exit 1
fi

GOOD=0
for _ in $(seq 1 12); do
    GOOD=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -o json | jq --arg n "$NODE02" '
        [.items[] | select(.metadata.deletionTimestamp == null)
         | select(.spec.nodeName == $n and .status.phase == "Running")
         | select(all(.status.conditions[]?; .type != "Ready" or .status == "True"))
         | select((.spec.containers[0].resources.requests.cpu // "") != "")] | length')
    [[ "$GOOD" == "3" ]] && break
    sleep 5
done
if [[ "$GOOD" != "3" ]]; then
    echo "❌ $GOOD of 3 Pods of '$DEPLOYMENT' are Ready on node02 with resource requests"
    exit 1
fi

echo "✅ All 3 Pods of '$DEPLOYMENT' are Ready on node02"
exit 0
