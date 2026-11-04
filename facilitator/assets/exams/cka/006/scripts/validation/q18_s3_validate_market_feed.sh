#!/bin/bash
set -e

NAMESPACE="sched-priority"
DEPLOYMENT="market-feed"
EXPECTED_REPLICAS=2

NODE=$(kubectl get nodes -l ck-x.io/alias=node03 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$NODE" ]]; then
    echo "❌ No node is labelled ck-x.io/alias=node03"
    exit 1
fi

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

PC=$(echo "$JSON" | jq -r '.spec.template.spec.priorityClassName // empty')
if [[ "$PC" != "critical-high" ]]; then
    echo "❌ '$DEPLOYMENT' uses priorityClassName '${PC:-<none>}', expected 'critical-high'"
    exit 1
fi

MEM=$(echo "$JSON" | jq -r '.spec.template.spec.containers[0].resources.requests.memory // empty')
if [[ "$MEM" != "512Mi" ]]; then
    echo "❌ '$DEPLOYMENT' requests '${MEM:-<none>}' of memory, expected '512Mi'"
    exit 1
fi

CONTAINER=$(echo "$JSON" | jq -r '.spec.template.spec.containers[0].name')
if [[ "$CONTAINER" != "feed" ]]; then
    echo "❌ The container is named '$CONTAINER', expected 'feed'"
    exit 1
fi

READY=$(echo "$JSON" | jq -r '.status.readyReplicas // 0')
if [[ "$READY" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' has $READY/$EXPECTED_REPLICAS ready replicas."
    echo "   The high-priority workload has to displace the batch job to fit on the node."
    exit 1
fi

NODES=$(kubectl get pods -n "$NAMESPACE" -l app=market-feed -o json \
    | jq -r '[.items[] | select(.status.phase=="Running") | .spec.nodeName] | unique | join(",")')
if [[ "$NODES" != "$NODE" ]]; then
    echo "❌ Running replicas are on '${NODES:-nowhere}', expected all of them on '$NODE'"
    exit 1
fi

echo "✅ '$DEPLOYMENT' runs $EXPECTED_REPLICAS replicas on '$NODE' at high priority"
exit 0
