#!/bin/bash
set -e

export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

if ! kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1; then
    echo "❌ The auxiliary API server does not answer"
    exit 1
fi

POD_SUBNET=$(kubectl get configmap kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' 2>/dev/null \
    | sed -n 's/^\s*podSubnet:\s*\(\S*\)\s*$/\1/p')
if [[ -z "$POD_SUBNET" ]]; then
    echo "❌ Cannot read the cluster's podSubnet from kubeadm-config"
    exit 1
fi

POOLS=$(kubectl get ippools.crd.projectcalico.org -o jsonpath='{range .items[*]}{.spec.cidr}{"\n"}{end}' 2>/dev/null || true)
if [[ -z "$POOLS" ]]; then
    echo "❌ Calico has no IP pool on the auxiliary cluster"
    exit 1
fi
if [[ "$(echo "$POOLS" | sort -u)" != "$POD_SUBNET" ]]; then
    echo "❌ Calico's IP pools are '$(echo $POOLS)', but the cluster's Pod CIDR is $POD_SUBNET"
    exit 1
fi

echo "✅ Calico allocates from the cluster's Pod CIDR $POD_SUBNET"
exit 0
