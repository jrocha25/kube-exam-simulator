#!/bin/bash
set -e

# The control plane node carries a NoSchedule taint, so "one Pod per node"
# is only reachable with a toleration for it -- which is the point of the
# question. Counting Ready nodes live keeps this correct if the cluster's node
# count ever changes.

NAMESPACE="ds-deice"
DS="deice"

if ! kubectl get daemonset "$DS" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ DaemonSet '$DS' not found in namespace '$NAMESPACE'"
    exit 1
fi

NODES=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')
if [[ -z "$NODES" || "$NODES" == "0" ]]; then
    echo "❌ No Ready nodes found; the cluster is not healthy"
    exit 1
fi

for _ in $(seq 1 12); do
    DESIRED=$(kubectl get daemonset "$DS" -n "$NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || true)
    READY=$(kubectl get daemonset "$DS" -n "$NAMESPACE" -o jsonpath='{.status.numberReady}' 2>/dev/null || true)
    [[ "${DESIRED:-0}" == "$NODES" && "${READY:-0}" == "$NODES" ]] && break
    sleep 5
done

if [[ "${DESIRED:-0}" != "$NODES" ]]; then
    echo "❌ DaemonSet '$DS' is scheduled onto ${DESIRED:-0} of the ${NODES} nodes"
    echo "   The control plane node is tainted; nothing lands there without a toleration."
    exit 1
fi
if [[ "${READY:-0}" != "$NODES" ]]; then
    echo "❌ DaemonSet '$DS' has ${READY:-0} ready Pods, expected ${NODES}"
    exit 1
fi

echo "✅ A ready '$DS' Pod runs on each of the ${NODES} nodes, control plane included"
exit 0
