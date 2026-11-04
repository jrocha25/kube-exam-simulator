#!/bin/bash

set -e

NAMESPACE="np-ports"
POLICY="payments-ingress"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so no traffic has been permitted"
    exit 1
fi

PAYMENTS_IP=$(kubectl get pod payments -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$PAYMENTS_IP" ]]; then
    echo "❌ Pod 'payments' in '$NAMESPACE' has no IP address"
    exit 1
fi

for _ in $(seq 1 6); do
    if kubectl exec frontend -n "$NAMESPACE" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${PAYMENTS_IP}:80" 2> /dev/null | grep -q "payments-http"; then
        echo "✅ Pod 'frontend' can reach 'payments' on port 80"
        exit 0
    fi
    sleep 5
done

echo "❌ Pod 'frontend' cannot reach 'payments' on port 80"
exit 1
