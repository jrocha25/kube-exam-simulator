#!/bin/bash
set -e

NAMESPACE="sched-berth"
POD="berth-manual"
IMAGE="nginx:1.27.4"
CP=$(grep '^controlplane=' /tmp/exam/nodes.env | cut -d= -f2)

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

NODE=$(echo "$JSON" | jq -r '.spec.nodeName // empty')
if [[ "$NODE" != "$CP" ]]; then
    echo "❌ Pod '$POD' is on '${NODE:-no node}', expected the control-plane node '$CP'"
    exit 1
fi

if [[ "$(echo "$JSON" | jq -r '.spec.containers[0].image')" != "$IMAGE" ]]; then
    echo "❌ Pod '$POD' does not run $IMAGE"
    exit 1
fi

if [[ "$(echo "$JSON" | jq '(.spec.nodeSelector // {} | length) + (.spec.affinity // {} | length)')" != "0" ]]; then
    echo "❌ Pod '$POD' carries a nodeSelector or affinity"
    exit 1
fi

# Every Pod carries the two not-ready/unreachable tolerations the admission
# plugin adds. Anything beyond those -- above all one for the control-plane
# taint, or a keyless Exists -- is a toleration the candidate wrote.
EXTRA=$(echo "$JSON" | jq '[.spec.tolerations // [] | .[]
    | select(.key != "node.kubernetes.io/not-ready" and .key != "node.kubernetes.io/unreachable")] | length')
if [[ "$EXTRA" != "0" ]]; then
    echo "❌ Pod '$POD' carries tolerations of its own"
    exit 1
fi

for _ in $(seq 1 6); do
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
done
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is '$PHASE', not Running"
    exit 1
fi

echo "✅ '$POD' runs on the control-plane node with no tolerations or placement rules"
exit 0
