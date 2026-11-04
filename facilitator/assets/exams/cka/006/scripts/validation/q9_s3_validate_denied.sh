#!/bin/bash
set -e

NAMESPACE="net-orders"

IP=$(kubectl get pod orders -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$IP" ]]; then
    echo "❌ The 'orders' Pod has no IP address"
    exit 1
fi

# wget must NOT succeed. A timeout is the expected outcome, so the exit status is
# the assertion and its output is only for the log.
if kubectl exec -n "$NAMESPACE" reporting -- \
        wget -qO- --timeout=8 "http://${IP}:80" >/dev/null 2>&1; then
    echo "❌ The 'reporting' Pod reached 'orders'. Only 'app=gateway' Pods may."
    exit 1
fi

echo "✅ The 'reporting' Pod is denied access to 'orders'"
exit 0
