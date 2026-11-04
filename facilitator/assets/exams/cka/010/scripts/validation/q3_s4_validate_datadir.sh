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

DATA_DIR="/var/lib/etcd"

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes aux true >/dev/null 2>&1; then
    echo "❌ Cannot reach the auxiliary cluster node over SSH"
    exit 1
fi

MANIFEST=$(ssh -o ConnectTimeout=10 aux "cat /etc/kubernetes/manifests/etcd.yaml" 2>/dev/null || true)
if [[ -z "$MANIFEST" ]]; then
    echo "❌ /etc/kubernetes/manifests/etcd.yaml is missing on the aux node"
    exit 1
fi
if ! grep -qE -- "--data-dir=${DATA_DIR}\$" <<<"$MANIFEST"; then
    echo "❌ etcd is not started with --data-dir=${DATA_DIR}"
    exit 1
fi
if ! grep -qE "^\s+path: ${DATA_DIR}\$" <<<"$MANIFEST"; then
    echo "❌ The etcd manifest no longer mounts ${DATA_DIR} from the node"
    exit 1
fi

READYZ=$(kubectl get --raw /readyz 2>/dev/null || true)
if [[ "$READYZ" != "ok" ]]; then
    echo "❌ The auxiliary cluster's API server is not ready (${READYZ:-no answer})"
    exit 1
fi

# "Fully working" means more than an API server that answers. After a restore
# every component that had a watch open against the old data -- the kubelet
# above all -- is waiting on resource versions the restored etcd has not
# reached, and a cluster in that state never starts another Pod. Prove it can.
NAMESPACE="etcd-restore"
PROBE="restore-probe-$$"
kubectl delete pod "$PROBE" -n "$NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1
kubectl run "$PROBE" -n "$NAMESPACE" --image=busybox:1.36 --restart=Never -- sleep 120 >/dev/null 2>&1 || true
for _ in $(seq 1 12); do
    PHASE=$(kubectl get pod "$PROBE" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
done
kubectl delete pod "$PROBE" -n "$NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ The cluster cannot start a Pod after the restore (probe stayed ${PHASE:-absent}) -- were the kubelet and control plane restarted?"
    exit 1
fi

echo "✅ etcd serves from ${DATA_DIR} and the cluster is healthy"
exit 0
