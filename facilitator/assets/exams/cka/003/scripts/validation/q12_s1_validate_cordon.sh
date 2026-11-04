#!/bin/bash
set -e

NODE="k3d-cluster-agent-1"

if ! kubectl get node "$NODE" &> /dev/null; then
    echo "❌ Node '$NODE' not found"
    exit 1
fi

UNSCHEDULABLE=$(kubectl get node "$NODE" -o jsonpath='{.spec.unschedulable}')
if [[ "$UNSCHEDULABLE" != "true" ]]; then
    echo "❌ Node '$NODE' is not marked unschedulable"
    exit 1
fi

echo "✅ Node '$NODE' is marked unschedulable"
exit 0
