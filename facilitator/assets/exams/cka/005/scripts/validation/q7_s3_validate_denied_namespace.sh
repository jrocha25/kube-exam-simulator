#!/bin/bash
set -e

TARGET_NS="net-tier"
CLIENT_NS="net-tier-others"
CLIENT="client-denied"

PAYMENTS_IP=$(kubectl get pod payments -n "$TARGET_NS" -o jsonpath='{.status.podIP}')
if [[ -z "$PAYMENTS_IP" ]]; then
    echo "❌ Pod 'payments' has no IP address"
    exit 1
fi

if kubectl exec "$CLIENT" -n "$CLIENT_NS" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://$PAYMENTS_IP:80" > /dev/null 2>&1; then
    echo "❌ Pod '$CLIENT' in the untrusted namespace '$CLIENT_NS' can still reach 'payments'"
    exit 1
fi

echo "✅ Pod '$CLIENT' in '$CLIENT_NS' is denied access to 'payments'"
exit 0
