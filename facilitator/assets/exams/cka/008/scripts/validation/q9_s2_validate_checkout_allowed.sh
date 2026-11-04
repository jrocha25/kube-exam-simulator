#!/bin/bash

set -e

# checkout is a Deployment, so the Pod name is not fixed -- resolve it through
# the label the Deployment stamps on its template.

NAMESPACE="np-ts-selector"
CLIENT_NS="np-ts-selector-clients"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

INVENTORY_IP=$(kubectl get pod inventory -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$INVENTORY_IP" ]]; then
    echo "❌ Pod 'inventory' in '$NAMESPACE' has no IP address"
    exit 1
fi

CHECKOUT=$(kubectl get pod -n "$CLIENT_NS" -l app=checkout \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2> /dev/null || true)
if [[ -z "$CHECKOUT" ]]; then
    echo "❌ No running 'checkout' Pod found in '$CLIENT_NS'"
    exit 1
fi

for _ in $(seq 1 6); do
    if kubectl exec "$CHECKOUT" -n "$CLIENT_NS" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${INVENTORY_IP}:80" > /dev/null 2>&1; then
        echo "✅ Pod '$CHECKOUT' can reach 'inventory' on port 80"
        exit 0
    fi
    sleep 5
done

echo "❌ Pod '$CHECKOUT' still cannot reach 'inventory' on port 80"
exit 1
