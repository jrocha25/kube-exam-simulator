#!/bin/bash
set -e

export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

if ! kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1; then
    sleep 10
    if ! kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1; then
        echo "❌ The auxiliary API server does not answer"
        exit 1
    fi
fi

# The scheduler and controller manager crash-loop while the API server is down
# and may take a moment to win their leases back.
for component in etcd kube-apiserver kube-controller-manager kube-scheduler; do
    READY=""
    for _ in $(seq 1 6); do
        READY=$(kubectl get pods -n kube-system -l component="$component" \
            -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
        [[ "$READY" == "True" ]] && break
        sleep 5
    done
    if [[ "$READY" != "True" ]]; then
        echo "❌ The $component Pod on the auxiliary cluster is not Ready"
        exit 1
    fi
done

echo "✅ All four control-plane Pods on the auxiliary cluster are Ready"
exit 0
