#!/bin/bash
set -e

NAMESPACE="net-billing"

IP=$(kubectl get pod archive -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$IP" ]]; then
    echo "❌ The 'archive' Pod has no IP address"
    exit 1
fi

if kubectl exec -n "$NAMESPACE" billing -- \
        wget -qO- --timeout=8 "http://${IP}:80" >/dev/null 2>&1; then
    echo "❌ 'billing' can reach the 'archive' Pod. That access had to stay blocked."
    exit 1
fi

echo "✅ 'billing' is still denied access to the 'archive' Pod"
exit 0
