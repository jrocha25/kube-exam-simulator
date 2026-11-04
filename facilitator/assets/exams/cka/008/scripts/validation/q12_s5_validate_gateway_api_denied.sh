#!/bin/bash

set -e

NAMESPACE="np-design"
CLIENT_NS="np-design-clients"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" -o json | jq '[.items[]] | length')
if [[ "$COUNT" == "0" ]]; then
    echo "❌ No NetworkPolicy exists in '$NAMESPACE', so nothing has been designed yet"
    exit 1
fi

API_IP=$(kubectl get pod api -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$API_IP" ]]; then
    echo "❌ Pod 'api' in '$NAMESPACE' has no IP address"
    exit 1
fi

if kubectl exec ingress-gw -n "$CLIENT_NS" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${API_IP}:8080" > /dev/null 2>&1; then
    echo "❌ Pod 'ingress-gw' can reach the api tier, bypassing the web tier"
    exit 1
fi

echo "✅ Pod 'ingress-gw' is denied access to the api tier"
exit 0
