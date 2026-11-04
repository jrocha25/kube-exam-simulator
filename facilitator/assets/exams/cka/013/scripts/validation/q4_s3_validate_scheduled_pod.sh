#!/bin/bash
set -e

NAMESPACE="sched-berth"
POD="berth-auto"
NODE01=$(grep '^node01=' /tmp/exam/nodes.env | cut -d= -f2)

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json --show-managed-fields 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

if [[ "$(echo "$JSON" | jq -r '.spec.nodeSelector["ck-x.io/alias"] // empty')" != "node01" ]]; then
    echo "❌ Pod '$POD' does not carry the nodeSelector ck-x.io/alias: node01"
    exit 1
fi

# The scheduler binds a Pod through the binding subresource, which leaves no
# managedFields entry for spec.nodeName. A nodeName written by a client does.
OWNED=$(echo "$JSON" | jq '[.metadata.managedFields[]? | select(.fieldsV1."f:spec"."f:nodeName" != null)] | length')
if [[ "$OWNED" != "0" ]]; then
    echo "❌ Pod '$POD' had its node set by hand, not by the scheduler"
    exit 1
fi

for _ in $(seq 1 6); do
    NODE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    [[ "$NODE" == "$NODE01" && "$PHASE" == "Running" ]] && break
    sleep 5
done
if [[ "$NODE" != "$NODE01" || "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is '$PHASE' on '${NODE:-no node}', expected Running on node01"
    exit 1
fi

echo "✅ '$POD' was bound to node01 by the scheduler"
exit 0
