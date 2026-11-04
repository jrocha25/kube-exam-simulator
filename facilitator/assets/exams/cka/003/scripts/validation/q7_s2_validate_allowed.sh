#!/bin/bash
set -e

NAMESPACE="net-guard"
POLICY="backend-ingress"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

BACKEND_IP=$(kubectl get pod backend -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$BACKEND_IP" ]]; then
    echo "❌ Pod 'backend' has no IP address"
    exit 1
fi

if ! kubectl exec frontend -n "$NAMESPACE" --request-timeout=60s -- wget -q -T 5 -t 1 -O- "http://$BACKEND_IP:80" > /dev/null 2>&1; then
    echo "❌ Pod 'frontend' cannot reach Pod 'backend' on port 80"
    exit 1
fi

echo "✅ Pod 'frontend' can reach Pod 'backend' on port 80"
exit 0
