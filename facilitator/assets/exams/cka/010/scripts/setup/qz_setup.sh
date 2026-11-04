#!/bin/bash
set -e

# Question 3, second half: take the snapshot the candidate restores from, then
# make the changes they have to roll back. Named qz so that it sorts after every
# other setup script -- a snapshot taken any earlier would be missing whatever
# the scripts after it staged on the auxiliary cluster, and the restore would
# quietly undo their work. A glob-order trick buys ordering, not isolation; the
# isolation comes from the auxiliary cluster itself.

AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux
NAMESPACE="etcd-restore"
SNAPSHOT=/opt/etcd-backup/aux-snapshot.db

if [ -f /tmp/exam/aux-cluster-unavailable ]; then
    echo "WARNING: the auxiliary cluster is unavailable, skipping the question 3 snapshot."
    exit 0
fi

export KUBECONFIG="$AUX_KUBECONFIG"

if ! kubectl get configmap ledger-state -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "WARNING: ledger-state is missing, so q3_setup.sh did not run; skipping the snapshot"
    exit 0
fi

if ! ssh -o ConnectTimeout=10 aux "SNAPSHOT=${SNAPSHOT} bash -s" <<'REMOTE'
set -e
export ETCDCTL_API=3
etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save "$SNAPSHOT" >/dev/null 2>&1
etcdutl snapshot status "$SNAPSHOT" >/dev/null 2>&1
echo "snapshot: $(stat -c %s "$SNAPSHOT") bytes at $SNAPSHOT"
REMOTE
then
    echo "WARNING: could not take the etcd snapshot on the aux node; question 3 has nothing to restore from"
    exit 0
fi

# The damage, planted only once the snapshot is safely on disk.
kubectl delete configmap ledger-state -n "$NAMESPACE" --ignore-not-found=true
kubectl create configmap migration-scratch -n "$NAMESPACE" \
    --from-literal=status=aborted --dry-run=client -o yaml | kubectl apply -f -

echo "Setup completed for Question 3 (snapshot taken, ledger-state deleted, by design)"
