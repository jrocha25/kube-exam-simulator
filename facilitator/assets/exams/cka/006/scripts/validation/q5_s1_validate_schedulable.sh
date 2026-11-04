#!/bin/bash
set -e

NODE=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$NODE" ]]; then
    echo "❌ No node is labelled ck-x.io/alias=node02"
    exit 1
fi

JSON=$(kubectl get node "$NODE" -o json)

UNSCHEDULABLE=$(echo "$JSON" | jq -r '.spec.unschedulable // false')
if [[ "$UNSCHEDULABLE" == "true" ]]; then
    echo "❌ Node '$NODE' is still cordoned"
    exit 1
fi

TAINT=$(echo "$JSON" | jq -r '[.spec.taints[]? | select(.key=="node.kubernetes.io/unschedulable")] | length')
if [[ "$TAINT" -gt 0 ]]; then
    echo "❌ Node '$NODE' still carries the unschedulable taint left by 'kubectl drain'"
    exit 1
fi

READY=$(echo "$JSON" | jq -r '.status.conditions[] | select(.type=="Ready") | .status')
if [[ "$READY" != "True" ]]; then
    echo "❌ Node '$NODE' is not Ready"
    exit 1
fi

echo "✅ Node '$NODE' is Ready and schedulable again"
exit 0
