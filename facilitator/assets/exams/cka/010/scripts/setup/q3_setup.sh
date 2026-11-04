#!/bin/bash
set -e

# Question 3: etcd backup and restore, staged on the auxiliary cluster.
#
# A restore rolls a whole cluster back in time, which is the textbook case for
# not doing it on the cluster fifteen other questions are running on. Over here
# the blast radius is questions 1 and 3, and both are written to survive either
# order (see answers.md).
#
# This script stages the *state to restore to*: a ConfigMap with an unguessable
# value, the tools the candidate needs on the node, and a record of etcd's
# cluster id. The snapshot itself is taken by qz_setup.sh -- the "z" sorts it
# after every other setup script, so anything else staged on the aux cluster is
# inside the snapshot -- and only then is the ConfigMap deleted.
#
# etcdctl/etcdutl come out of the etcd image already on the node, the same way
# cka/006's question 4 does it; kindest/node does not ship them.

AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux
NAMESPACE="etcd-restore"

mkdir -p /tmp/exam/q3

if [ -f /tmp/exam/aux-cluster-unavailable ]; then
    echo "WARNING: the auxiliary cluster is unavailable, skipping question 3 setup."
    echo "WARNING: see the warning from q0_setup.sh for the fix."
    exit 0
fi

export KUBECONFIG="$AUX_KUBECONFIG"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete configmap migration-scratch -n "$NAMESPACE" --ignore-not-found=true

# The value the restored ConfigMap has to carry. Random, so a candidate who
# recreates the object by hand cannot guess it -- though the cluster id check
# in q3_s3 is what really proves a restore happened.
LEDGER_ID=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
echo "$LEDGER_ID" > /tmp/exam/q3/ledger-id
kubectl create configmap ledger-state -n "$NAMESPACE" \
    --from-literal=ledger-id="$LEDGER_ID" --from-literal=period=2026-Q3 \
    --dry-run=client -o yaml | kubectl apply -f -

ssh -o ConnectTimeout=10 aux 'bash -s' <<'REMOTE'
set -e
mkdir -p /opt/etcd-backup
rm -f /opt/etcd-backup/aux-snapshot.db /opt/etcd-backup/before-restore.db

if command -v etcdctl >/dev/null 2>&1 && command -v etcdutl >/dev/null 2>&1; then
    echo "etcdctl already installed"
    exit 0
fi

ETCD_IMAGE=$(grep -m1 'image:' /etc/kubernetes/manifests/etcd.yaml | awk '{print $2}')
MOUNT=/mnt/ck-x-etcd-image
umount "$MOUNT" 2>/dev/null || true
mkdir -p "$MOUNT"
if ctr -n k8s.io image mount "$ETCD_IMAGE" "$MOUNT" >/dev/null 2>&1; then
    cp "$MOUNT/usr/local/bin/etcdctl" /usr/local/bin/etcdctl
    cp "$MOUNT/usr/local/bin/etcdutl" /usr/local/bin/etcdutl
    chmod +x /usr/local/bin/etcdctl /usr/local/bin/etcdutl
    umount "$MOUNT" 2>/dev/null || true
    rmdir "$MOUNT" 2>/dev/null || true
    echo "Installed etcdctl and etcdutl from ${ETCD_IMAGE}"
else
    echo "WARNING: could not extract etcdctl from ${ETCD_IMAGE}."
    echo "WARNING: question 3 can still be solved with"
    echo "WARNING:   kubectl -n kube-system exec etcd-<node> -- etcdctl ..."
fi
REMOTE

# etcd's cluster id. "etcdutl snapshot restore" bootstraps a brand-new
# single-member cluster from the snapshot data, so a genuine restore always
# changes it, and no amount of kubectl can.
CLUSTER_ID=$(ssh -o ConnectTimeout=10 aux "etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key endpoint status -w json 2>/dev/null" \
    | grep -o '"cluster_id":[0-9]*' | head -1 | cut -d: -f2 || true)
if [ -n "$CLUSTER_ID" ]; then
    echo "$CLUSTER_ID" > /tmp/exam/q3/cluster-id
    echo "etcd cluster id before the exam: $CLUSTER_ID"
else
    echo "WARNING: could not read the etcd cluster id; q3_s3 will not be able to grade"
fi

echo "Setup completed for Question 3 (state staged; the snapshot is taken by qz_setup.sh)"
