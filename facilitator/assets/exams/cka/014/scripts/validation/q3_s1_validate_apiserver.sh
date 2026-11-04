#!/bin/bash
set -e

# Staged on the auxiliary cluster, so this script drives that one.
export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

AUX_UP=no
for _ in 1 2 3 4; do
    kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1 && { AUX_UP=yes; break; }
    sleep 10
done
if [[ "$AUX_UP" != yes ]]; then
    echo "❌ The auxiliary API server does not answer /readyz"
    exit 1
fi

if ! kubectl --request-timeout=10s get --raw '/readyz/etcd' >/dev/null 2>&1; then
    echo "❌ The auxiliary API server answers but reports etcd unhealthy"
    exit 1
fi

POD=$(kubectl get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
READY=$(kubectl get pod "$POD" -n kube-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [[ "$READY" != "True" ]]; then
    echo "❌ The API server answers but its mirror Pod '${POD:-?}' is not Ready"
    exit 1
fi

echo "✅ The auxiliary API server answers and its etcd check passes"
exit 0
