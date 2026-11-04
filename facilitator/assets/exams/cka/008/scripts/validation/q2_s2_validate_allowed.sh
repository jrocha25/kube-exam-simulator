#!/bin/bash

set -e

NAMESPACE="np-tiers"
POLICY="api-allow-frontend"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so no traffic has been permitted"
    exit 1
fi

API_IP=$(kubectl get pod api -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$API_IP" ]]; then
    echo "❌ Pod 'api' in '$NAMESPACE' has no IP address"
    exit 1
fi

for _ in $(seq 1 6); do
    if kubectl exec frontend -n "$NAMESPACE" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${API_IP}:80" > /dev/null 2>&1; then
        echo "✅ Pod 'frontend' can reach 'api' on port 80"
        exit 0
    fi
    sleep 5
done

echo "❌ Pod 'frontend' cannot reach 'api' on port 80"
exit 1
