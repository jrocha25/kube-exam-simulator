#!/bin/bash
set -e

# Question 2: node03 is taken out of the lab cluster with kubeadm reset and its
# Node object deleted, so the candidate has to bring it back with kubeadm join --
# token from the control plane, discovery hash, join on the node.
#
# node03 belongs to this question alone: nothing else in the lab pins to it, and
# no validation script counts nodes globally, so a cluster that is one worker
# short for most of the exam breaks nothing. The node's kind name is read from
# the alias map q0_setup.sh wrote *before* the Node object (and its
# ck-x.io/alias label) disappears; q2's validation scripts read the same file.
#
# kubeadm reset stops the kubelet, wipes /etc/kubernetes and /var/lib/kubelet,
# and removes the CNI configuration, which is exactly the state the question
# describes. The node's sshd is a plain systemd unit and survives all of it.

NAMESPACE="join-node"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: skipping question 2 setup, there is no shell on the nodes"
    exit 0
fi

NODE03=$(grep '^node03=' /tmp/exam/nodes.env 2>/dev/null | cut -d= -f2 || true)
if [ -z "$NODE03" ]; then
    NODE03=$(kubectl get nodes -l ck-x.io/alias=node03 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [ -z "$NODE03" ]; then
    echo "WARNING: could not resolve node03; skipping question 2 setup"
    exit 0
fi

if ! kubectl get node "$NODE03" >/dev/null 2>&1; then
    echo "node '$NODE03' is already out of the cluster; nothing to stage"
else
    kubectl cordon "$NODE03" >/dev/null 2>&1 || true
fi

ssh -o ConnectTimeout=10 node03 'bash -s' <<'REMOTE'
set -e
if [ -f /etc/kubernetes/kubelet.conf ]; then
    kubeadm reset -f >/dev/null 2>&1 || echo "WARNING: kubeadm reset exited non-zero"
fi
rm -rf /etc/cni/net.d
systemctl stop kubelet >/dev/null 2>&1 || true
echo "node03: kubelet $(systemctl is-active kubelet 2>/dev/null || true), /etc/kubernetes holds: $(ls /etc/kubernetes 2>/dev/null | tr '\n' ' ')"
REMOTE

kubectl delete node "$NODE03" --ignore-not-found=true --wait=false

for _ in $(seq 1 12); do
    kubectl get node "$NODE03" >/dev/null 2>&1 || break
    sleep 5
done
if kubectl get node "$NODE03" >/dev/null 2>&1; then
    echo "WARNING: node '$NODE03' is still listed after being deleted"
fi

echo "Setup completed for Question 2 (node03 / $NODE03 is out of the cluster, by design)"
