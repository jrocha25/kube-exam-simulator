#!/bin/bash
set -e

# Staged on the auxiliary cluster, so this script drives that one rather than the
# lab's own. Re-exporting KUBECONFIG overrides the caller's for this process only.
export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

# Bounded retry: a control plane that was repaired a moment ago may still be
# coming up, and a candidate who just finished should not lose the question to that.
AUX_UP=no
for _ in 1 2 3 4; do
    kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1 && { AUX_UP=yes; break; }
    sleep 10
done
if [[ "$AUX_UP" != yes ]]; then
    echo "❌ The auxiliary API server does not answer"
    exit 1
fi

POD=$(kubectl get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
    echo "❌ No kube-apiserver mirror Pod is registered on the auxiliary cluster"
    exit 1
fi

READY=$(kubectl get pod "$POD" -n kube-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [[ "$READY" != "True" ]]; then
    echo "❌ The API server answers but its Pod '$POD' is not Ready"
    exit 1
fi

echo "✅ The auxiliary API server answers and '$POD' is Ready"
exit 0
