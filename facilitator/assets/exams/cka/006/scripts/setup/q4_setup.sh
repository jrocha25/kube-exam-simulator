#!/bin/bash
set -e

# Question 4: an etcd snapshot. Nothing needs breaking -- the exercise is getting
# etcdctl to talk to the kubeadm etcd static pod at all, which means reading the
# three certificate paths out of /etc/kubernetes/manifests/etcd.yaml.
#
# The real exam ships etcdctl on the control plane; kindest/node does not. Rather
# than download a release during warm-up, lift the binaries out of the etcd image
# that is already on the node -- offline, and always the version that matches the
# running server.

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: skipping question 4 setup, there is no shell on the nodes"
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
    echo "Installed etcdctl from ${ETCD_IMAGE}"
else
    echo "WARNING: could not extract etcdctl from ${ETCD_IMAGE}."
    echo "WARNING: question 4 can still be solved with"
    echo "WARNING:   kubectl -n kube-system exec etcd-<node> -- etcdctl ..."
fi
REMOTE

echo "Setup completed for Question 4"
