#!/bin/bash
set -e

NAMESPACE="net-tier"

PAYMENTS_IP=$(kubectl get pod payments -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$PAYMENTS_IP" ]]; then
    echo "❌ Pod 'payments' has no IP address"
    exit 1
fi

if kubectl exec neighbour -n "$NAMESPACE" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://$PAYMENTS_IP:80" > /dev/null 2>&1; then
    echo "❌ Pod 'neighbour' in the same namespace can still reach 'payments'"
    exit 1
fi

echo "✅ Pod 'neighbour' in '$NAMESPACE' is denied access to 'payments'"
exit 0
