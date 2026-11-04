#!/bin/bash
set -e

# Question 2: an etcd snapshot of the lab cluster, proven by an offline restore.
#
# The real exam ships etcdctl on the control plane; kindest/node does not. Lift
# etcdctl and etcdutl out of the etcd image already on the node -- offline, and
# always the version that matches the running server (cka/006 q4 does the same).
#
# The validation scripts prove the snapshot was taken *after* the marker
# ConfigMap the candidate creates, by comparing the snapshot's revision with the
# ConfigMap's resourceVersion, and that the running etcd was never restarted,
# by comparing its container id with the one recorded here.

NAMESPACE="etcd-cutover"
STATE_DIR=/tmp/exam/q2

mkdir -p "$STATE_DIR"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete configmap cutover-marker -n "$NAMESPACE" --ignore-not-found=true

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: skipping question 2 setup, there is no shell on the nodes"
    exit 0
fi

ssh -o ConnectTimeout=10 controlplane 'bash -s' <<'REMOTE'
set -e
rm -rf /opt/etcd-backup
mkdir -p /opt/etcd-backup

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
fi
REMOTE

CP=$(grep '^controlplane=' /tmp/exam/nodes.env | cut -d= -f2)
kubectl get pod "etcd-${CP}" -n kube-system \
    -o jsonpath='{.status.containerStatuses[0].containerID}' > "$STATE_DIR/etcd-container" 2>/dev/null \
    || echo "WARNING: could not record the etcd container id"

echo "Setup completed for Question 2"
