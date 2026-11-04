#!/bin/bash
set -e

# Question 11, on the auxiliary cluster: take its CNI away so the candidate has
# to install one.
#
# ORDER MATTERS: question 3 takes this same cluster's API server down, and this
# script needs that API server to delete Calico. Glob order (q0, q1, q10, q11,
# ..., q2, q3, ...) runs this script before q3_setup.sh; keep it that way.
#
# The Calico images stay cached on the node, so a re-install needs no network.

export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

FILES=/tmp/exam-assets/scripts/setup/files
CALICO="$FILES/calico-v3.32.1.yaml"
FLANNEL="$FILES/kube-flannel-v0.28.10.yml"

if [ -f /tmp/exam/aux-cluster-unavailable ]; then
    echo "WARNING: the auxiliary cluster is unavailable, skipping setup for question 11"
    exit 0
fi

ssh -o ConnectTimeout=10 aux 'mkdir -p /root/cni && rm -f /root/cni/*'
ssh -o ConnectTimeout=10 aux 'cat > /root/cni/calico.yaml' < "$CALICO"
ssh -o ConnectTimeout=10 aux 'cat > /root/cni/kube-flannel.yml' < "$FLANNEL"

kubectl delete -f "$CALICO" --ignore-not-found=true --wait=false >/dev/null 2>&1 \
    || echo "WARNING: deleting Calico from the auxiliary cluster reported errors"

# Wait for the DaemonSet's Pods to go, then remove the CNI configuration they
# left behind; without it the kubelet reports the network as not ready.
for _ in $(seq 1 24); do
    [ -z "$(kubectl get pods -n kube-system -l k8s-app=calico-node -o name 2>/dev/null)" ] && break
    sleep 5
done
ssh -o ConnectTimeout=10 aux 'rm -f /etc/cni/net.d/10-calico.conflist /etc/cni/net.d/calico-kubeconfig'

NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
STAGED=no
for _ in $(seq 1 18); do
    READY=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [ "$READY" != "True" ]; then
        STAGED=yes
        break
    fi
    sleep 5
done
[ "$STAGED" = yes ] || echo "WARNING: the auxiliary node still reports Ready after Calico was removed"

echo "Setup for question 11 completed"
