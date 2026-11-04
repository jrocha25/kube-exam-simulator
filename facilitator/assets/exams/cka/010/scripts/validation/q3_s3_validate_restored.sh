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

RECORDED_FILE="/tmp/exam/q3/cluster-id"

if [[ ! -s "$RECORDED_FILE" ]]; then
    echo "❌ Setup did not record the etcd cluster id, so this step cannot be graded"
    exit 1
fi
RECORDED=$(cat "$RECORDED_FILE")

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes aux true >/dev/null 2>&1; then
    echo "❌ Cannot reach the auxiliary cluster node over SSH"
    exit 1
fi

# "etcdutl snapshot restore" bootstraps a new cluster from the snapshot data and
# gives it a new cluster id. Recreating the ConfigMap by hand leaves the id
# alone, which is what makes this the check that a restore really happened.
CURRENT=$(ssh -o ConnectTimeout=10 aux "etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key endpoint status -w json 2>/dev/null" \
    | grep -o '"cluster_id":[0-9]*' | head -1 | cut -d: -f2 || true)

if [[ -z "$CURRENT" ]]; then
    echo "❌ Could not read the etcd cluster id on the aux node"
    exit 1
fi
if [[ "$CURRENT" == "$RECORDED" ]]; then
    echo "❌ etcd still has the cluster id it had before the exam -- it was not restored from a snapshot"
    exit 1
fi

echo "✅ etcd is serving a restored data set (cluster id changed)"
exit 0
