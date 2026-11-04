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

MAX_AGE_SECONDS=60

POD=$(kubectl get pods -n kube-system -l component=kube-controller-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
    echo "❌ No kube-controller-manager mirror Pod is registered on the auxiliary cluster"
    exit 1
fi

for _ in $(seq 1 6); do
    READY=$(kubectl get pod "$POD" -n kube-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    [[ "$READY" == "True" ]] && break
    sleep 5
done
if [[ "$READY" != "True" ]]; then
    echo "❌ The controller manager Pod '$POD' is not Ready"
    exit 1
fi

# A Ready container is not yet a working controller manager: one that cannot
# talk to the API server still passes its own health check for a while. The
# leader lease is only renewed by a controller manager that is really working.
RENEW=$(kubectl get lease kube-controller-manager -n kube-system -o jsonpath='{.spec.renewTime}' 2>/dev/null || true)
if [[ -z "$RENEW" ]]; then
    echo "❌ The controller manager has never taken its leader lease"
    exit 1
fi
AGE=$(( $(date -u +%s) - $(date -u -d "$RENEW" +%s) ))
if (( AGE > MAX_AGE_SECONDS )); then
    echo "❌ The controller manager's leader lease was last renewed ${AGE}s ago"
    exit 1
fi

echo "✅ The controller manager is Ready and renewed its lease ${AGE}s ago"
exit 0
