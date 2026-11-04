#!/bin/bash

set -e

# 'batch' carries a role label that is in neither allowed set, so it must be shut
# out of both ports.

NAMESPACE="np-ports"
POLICY="payments-ingress"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so nothing has been solved yet"
    exit 1
fi

PAYMENTS_IP=$(kubectl get pod payments -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$PAYMENTS_IP" ]]; then
    echo "❌ Pod 'payments' in '$NAMESPACE' has no IP address"
    exit 1
fi

for port in 80 9090; do
    if kubectl exec batch -n "$NAMESPACE" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${PAYMENTS_IP}:${port}" > /dev/null 2>&1; then
        echo "❌ Pod 'batch' can reach 'payments' on port ${port}"
        exit 1
    fi
done

echo "✅ Pod 'batch' is denied access to both ports"
exit 0
