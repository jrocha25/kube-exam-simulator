#!/bin/bash
set -e

# node03's ck-x.io/alias label went with its Node object when setup removed it
# from the cluster, so its kind name is read from the map q0_setup.sh wrote
# beforehand rather than resolved through the label.
NODE=$(grep "^node03=" /tmp/exam/nodes.env 2>/dev/null | cut -d= -f2 || true)
NODE=${NODE:-cluster-worker3}

if ! kubectl get node "$NODE" >/dev/null 2>&1; then
    echo "❌ Node '$NODE' is not part of the cluster"
    exit 1
fi

UNSCHEDULABLE=$(kubectl get node "$NODE" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)
if [[ "$UNSCHEDULABLE" == "true" ]]; then
    echo "❌ Node '$NODE' is cordoned"
    exit 1
fi

echo "✅ Node '$NODE' is schedulable"
exit 0
