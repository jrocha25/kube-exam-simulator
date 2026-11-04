#!/bin/bash
set -e

# Staged on the auxiliary cluster, so this script drives that one rather than the
# lab's own. The caller exports KUBECONFIG for the primary cluster before every
# validation script; re-exporting here overrides it for this process only.
export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

# Bounded retry: a kubelet restart on that node -- part of both questions set
# there -- takes its API server down for half a minute, and a candidate who
# finished a moment ago should not lose the question to that.
AUX_UP=no
for _ in 1 2 3 4; do
    kubectl --request-timeout=10s get nodes >/dev/null 2>&1 && { AUX_UP=yes; break; }
    sleep 5
done
if [[ "$AUX_UP" != yes ]]; then
    echo "❌ The auxiliary cluster is unreachable, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

UNSCHEDULABLE=$(kubectl get node "$NODE" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)
if [[ "$UNSCHEDULABLE" == "true" ]]; then
    echo "❌ Node '$NODE' is still cordoned"
    exit 1
fi

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes aux true >/dev/null 2>&1; then
    echo "❌ Cannot reach the auxiliary cluster node over SSH"
    exit 1
fi

HELD=$(ssh -o ConnectTimeout=10 aux "apt-mark showhold" 2>/dev/null || true)
for pkg in kubeadm kubelet kubectl; do
    if ! grep -qx "$pkg" <<<"$HELD"; then
        echo "❌ Package '$pkg' is not on hold on the aux node"
        exit 1
    fi
done

echo "✅ Node '$NODE' is schedulable and kubeadm, kubelet and kubectl are held"
exit 0
