#!/bin/bash
set -e

BEFORE="/tmp/exam/q4/before.env"
NAMESPACE="kube-system"

if [[ ! -s "$BEFORE" ]]; then
    echo "❌ Setup did not record the certificate expiry dates, so this step cannot be graded"
    exit 1
fi
# shellcheck disable=SC1090
source "$BEFORE"

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes controlplane true >/dev/null 2>&1; then
    echo "❌ Cannot reach the control plane node over SSH"
    exit 1
fi

# "kubeadm certs renew all" also rotates the client certificates embedded in
# the kubeconfigs the controller manager and scheduler authenticate with.
for conf in controller-manager scheduler; do
    var="${conf//-/_}_conf"
    recorded="${!var:-}"
    END=$(ssh -o ConnectTimeout=10 controlplane \
        "grep client-certificate-data /etc/kubernetes/${conf}.conf | awk '{print \$2}' | base64 -d | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2" || true)
    if [[ -z "$END" ]]; then
        echo "❌ Could not read the client certificate in /etc/kubernetes/${conf}.conf"
        exit 1
    fi
    if [[ -n "$recorded" && "$(date -d "$END" +%s)" -le "$recorded" ]]; then
        echo "❌ The client certificate in ${conf}.conf was not renewed"
        exit 1
    fi
done

# And those two components only pick the new kubeconfig up on restart: their
# containers must have started after setup recorded the "before" state.
for component in kube-controller-manager kube-scheduler; do
    STARTED=$(kubectl get pods -n "$NAMESPACE" -l "component=${component},tier=control-plane" \
        -o jsonpath='{.items[0].status.containerStatuses[0].state.running.startedAt}' 2>/dev/null || true)
    if [[ -z "$STARTED" ]]; then
        echo "❌ ${component} is not running"
        exit 1
    fi
    if [[ -n "${setup_time:-}" && "$(date -d "$STARTED" +%s)" -le "$setup_time" ]]; then
        echo "❌ ${component} has not been restarted since the exam started (running since $STARTED)"
        exit 1
    fi
done

READYZ=$(kubectl get --raw /readyz 2>/dev/null || true)
if [[ "$READYZ" != "ok" ]]; then
    echo "❌ The API server is not ready (${READYZ:-no answer})"
    exit 1
fi

echo "✅ The kubeconfigs were renewed, the components restarted, and the cluster is healthy"
exit 0
