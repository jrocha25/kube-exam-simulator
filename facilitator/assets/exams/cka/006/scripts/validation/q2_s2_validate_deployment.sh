#!/bin/bash
set -e

NAMESPACE="sched-batch"
DEPLOYMENT="batch-runner"
EXPECTED_REPLICAS=2

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC_REPLICAS=$(echo "$JSON" | jq -r '.spec.replicas')
if [[ "$SPEC_REPLICAS" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' declares $SPEC_REPLICAS replicas, expected $EXPECTED_REPLICAS"
    exit 1
fi

READY=$(echo "$JSON" | jq -r '.status.readyReplicas // 0')
if [[ "$READY" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' has $READY/$EXPECTED_REPLICAS ready replicas"
    exit 1
fi

# The pin has to survive: moving the workload to another node would make the pods
# run without the kubelet fault ever being fixed.
PIN=$(echo "$JSON" | jq -r '.spec.template.spec.nodeSelector["ck-x.io/alias"] // empty')
if [[ "$PIN" != "node01" ]]; then
    echo "❌ '$DEPLOYMENT' is no longer pinned to node01 (nodeSelector: ${PIN:-<none>})"
    exit 1
fi

MEM=$(echo "$JSON" | jq -r '.spec.template.spec.containers[0].resources.requests.memory // empty')
if [[ "$MEM" != "3Gi" ]]; then
    echo "❌ '$DEPLOYMENT' requests '${MEM:-<none>}' of memory, expected the original '3Gi'"
    exit 1
fi

OFF_NODE=$(kubectl get pods -n "$NAMESPACE" -l app=batch-runner \
    -o json | jq -r '[.items[] | select(.status.phase=="Running") | .spec.nodeName] | unique | join(",")')
NODE01=$(kubectl get nodes -l ck-x.io/alias=node01 -o jsonpath='{.items[0].metadata.name}')
if [[ "$OFF_NODE" != "$NODE01" ]]; then
    echo "❌ Running pods are on '$OFF_NODE', expected all of them on '$NODE01'"
    exit 1
fi

echo "✅ Both '$DEPLOYMENT' replicas are Running on node01"
exit 0
