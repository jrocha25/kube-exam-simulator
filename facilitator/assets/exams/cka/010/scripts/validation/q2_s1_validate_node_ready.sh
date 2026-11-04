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

for _ in $(seq 1 12); do
    READY=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$READY" == "True" ]] && break
    sleep 5
done

if [[ "$READY" != "True" ]]; then
    echo "❌ Node '$NODE' is in the cluster but not Ready"
    exit 1
fi

echo "✅ Node '$NODE' is back in the cluster and Ready"
exit 0
