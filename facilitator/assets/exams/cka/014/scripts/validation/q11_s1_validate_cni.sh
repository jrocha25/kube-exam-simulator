#!/bin/bash
set -e

export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

if ! kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1; then
    echo "❌ The auxiliary API server does not answer (question 3 comes first)"
    exit 1
fi

# The CNI has to enforce NetworkPolicy; of the two manifests offered, only
# Calico does.
DS=$(kubectl get daemonset calico-node -n kube-system -o json 2>/dev/null || true)
if [[ -z "$DS" ]]; then
    echo "❌ No calico-node DaemonSet on the auxiliary cluster; a CNI that enforces NetworkPolicy is required"
    exit 1
fi

READY=""
for _ in $(seq 1 12); do
    READY=$(kubectl get node -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    DESIRED=$(kubectl get daemonset calico-node -n kube-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || true)
    NREADY=$(kubectl get daemonset calico-node -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || true)
    [[ "$READY" == "True" && -n "$DESIRED" && "$DESIRED" == "$NREADY" && "$DESIRED" != "0" ]] && break
    sleep 5
done
if [[ "$READY" != "True" ]]; then
    echo "❌ The auxiliary node is not Ready"
    exit 1
fi
if [[ "$DESIRED" != "$NREADY" || "$DESIRED" == "0" ]]; then
    echo "❌ calico-node is not ready ($NREADY of $DESIRED)"
    exit 1
fi

echo "✅ Calico is running and the auxiliary node is Ready"
exit 0
