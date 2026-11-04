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

SNAPSHOT="/opt/etcd-backup/before-restore.db"
MIN_BYTES=1000000

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes aux true >/dev/null 2>&1; then
    echo "❌ Cannot reach the auxiliary cluster node over SSH"
    exit 1
fi

SIZE=$(ssh -o ConnectTimeout=10 aux "stat -c %s '$SNAPSHOT' 2>/dev/null" || true)
if [[ -z "$SIZE" ]]; then
    echo "❌ '$SNAPSHOT' does not exist on the aux node"
    exit 1
fi
if [[ "$SIZE" -lt "$MIN_BYTES" ]]; then
    echo "❌ '$SNAPSHOT' is only ${SIZE} bytes -- too small to be a real etcd snapshot"
    exit 1
fi

# A file of the right size is not proof of a usable backup: ask etcd itself.
if ! ssh -o ConnectTimeout=10 aux "etcdutl snapshot status '$SNAPSHOT' >/dev/null 2>&1 \
        || ETCDCTL_API=3 etcdctl snapshot status '$SNAPSHOT' >/dev/null 2>&1"; then
    echo "❌ '$SNAPSHOT' exists but etcd cannot read it as a snapshot"
    exit 1
fi

echo "✅ A valid etcd snapshot of ${SIZE} bytes exists at '$SNAPSHOT'"
exit 0
