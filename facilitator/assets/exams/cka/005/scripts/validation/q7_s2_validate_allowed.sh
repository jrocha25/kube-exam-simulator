#!/bin/bash
set -e

TARGET_NS="net-tier"
CLIENT_NS="net-tier-clients"
CLIENT="client-allowed"

if ! kubectl get networkpolicy payments-ingress -n "$TARGET_NS" &> /dev/null; then
    echo "❌ NetworkPolicy 'payments-ingress' not found in namespace '$TARGET_NS'"
    exit 1
fi

PAYMENTS_IP=$(kubectl get pod payments -n "$TARGET_NS" -o jsonpath='{.status.podIP}')
if [[ -z "$PAYMENTS_IP" ]]; then
    echo "❌ Pod 'payments' has no IP address"
    exit 1
fi

if ! kubectl exec "$CLIENT" -n "$CLIENT_NS" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://$PAYMENTS_IP:80" > /dev/null 2>&1; then
    echo "❌ Pod '$CLIENT' in '$CLIENT_NS' cannot reach 'payments' on port 80"
    exit 1
fi

echo "✅ Pod '$CLIENT' in the trusted namespace can reach 'payments' on port 80"
exit 0
