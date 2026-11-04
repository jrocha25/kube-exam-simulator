#!/bin/bash
set -e

# Question 5: change the kubelet configuration the kubeadm way. The cluster-wide
# copy lives in the kube-system ConfigMap "kubelet-config", which is what every
# future "kubeadm join" downloads; "kubeadm upgrade node phase kubelet-config"
# rewrites a node's /var/lib/kubelet/config.yaml from it, and the kubelet only
# reads that file at start.
#
# Record both the ConfigMap and controlplane's config.yaml so the validation can
# tell "added two keys" from "rewrote the file by hand and lost something".
# kind's KubeletConfiguration round-trips through the phase unchanged (checked on
# kindest/node v1.34.8), so the only expected difference is the two new keys.

NAMESPACE="kubeadm-logs"
STATE_DIR=/tmp/exam/q5

mkdir -p "$STATE_DIR"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl get configmap kubelet-config -n kube-system -o jsonpath='{.data.kubelet}' > "$STATE_DIR/configmap.orig" \
    || echo "WARNING: could not record the kubelet-config ConfigMap"

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: skipping question 5 setup, there is no shell on the nodes"
    exit 0
fi

ssh -n -o ConnectTimeout=10 controlplane 'cat /var/lib/kubelet/config.yaml' > "$STATE_DIR/config.yaml.orig" \
    || echo "WARNING: could not record controlplane's kubelet configuration"

if grep -q '^containerLogMax' "$STATE_DIR/configmap.orig" 2>/dev/null; then
    echo "WARNING: the kubelet-config ConfigMap already sets containerLogMax*; question 5 starts half solved"
fi

echo "Setup completed for Question 5"
