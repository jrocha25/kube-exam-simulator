#!/bin/bash
set -e

# node03's ck-x.io/alias label went with its Node object when setup removed it
# from the cluster, so its kind name is read from the map q0_setup.sh wrote
# beforehand rather than resolved through the label.
NODE=$(grep "^node03=" /tmp/exam/nodes.env 2>/dev/null | cut -d= -f2 || true)
NODE=${NODE:-cluster-worker3}

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes node03 true >/dev/null 2>&1; then
    echo "❌ Cannot reach node03 over SSH"
    exit 1
fi

ACTIVE=$(ssh -o ConnectTimeout=10 node03 "systemctl is-active kubelet" 2>/dev/null || true)
if [[ "$ACTIVE" != "active" ]]; then
    echo "❌ The kubelet on node03 is '${ACTIVE:-unknown}', expected active"
    exit 1
fi

if ! ssh -o ConnectTimeout=10 node03 "test -s /etc/kubernetes/kubelet.conf" 2>/dev/null; then
    echo "❌ node03 has no /etc/kubernetes/kubelet.conf -- the kubelet has not been joined to a cluster"
    exit 1
fi

echo "✅ The kubelet on node03 is running with a cluster kubeconfig"
exit 0
