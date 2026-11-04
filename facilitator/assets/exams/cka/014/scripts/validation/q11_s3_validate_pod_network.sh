#!/bin/bash
set -e

export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

NAMESPACE="cni-check"
POD="cni-probe"

if ! kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1; then
    echo "❌ The auxiliary API server does not answer"
    exit 1
fi

POD_SUBNET=$(kubectl get configmap kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' 2>/dev/null \
    | sed -n 's/^\s*podSubnet:\s*\(\S*\)\s*$/\1/p')
[[ -z "$POD_SUBNET" ]] && POD_SUBNET=192.169.0.0/16

cleanup() { kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl run "$POD" -n "$NAMESPACE" --image=busybox:1.36 --restart=Never \
    --overrides='{"spec":{"terminationGracePeriodSeconds":0}}' -- sleep 300 >/dev/null 2>&1 || true

PHASE=""
for _ in $(seq 1 12); do
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
done
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ A new Pod on the auxiliary cluster does not start (phase '${PHASE:-none}')"
    exit 1
fi

IP=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if ! python3 -c "import ipaddress,sys; sys.exit(0 if ipaddress.ip_address('$IP') in ipaddress.ip_network('$POD_SUBNET') else 1)" 2>/dev/null; then
    echo "❌ A new Pod got the address $IP, outside the Pod CIDR $POD_SUBNET"
    exit 1
fi

echo "✅ A new Pod starts and gets $IP from $POD_SUBNET"
exit 0
