#!/bin/bash
set -e

NODE="k3d-cluster-agent-1"

if ! kubectl get node "$NODE" &> /dev/null; then
    echo "❌ Node '$NODE' not found"
    exit 1
fi

REMAINING=$(kubectl get pods --all-namespaces -o json | jq --arg node "$NODE" '[.items[]
  | select(.spec.nodeName == $node)
  | select(.status.phase != "Succeeded" and .status.phase != "Failed")
  | select(((.metadata.ownerReferences // []) | map(.kind) | index("DaemonSet")) | not)] | length')

if [[ "$REMAINING" != "0" ]]; then
    echo "❌ $REMAINING non-DaemonSet Pod(s) are still running on node '$NODE'"
    exit 1
fi

echo "✅ Node '$NODE' has been drained of all non-DaemonSet Pods"
exit 0
