#!/bin/bash

set -e

NAMESPACE="np-additive"
POLICY="allow-backup"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so 'backup' has not been permitted"
    exit 1
fi

REPORTS_IP=$(kubectl get pod reports -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$REPORTS_IP" ]]; then
    echo "❌ Pod 'reports' in '$NAMESPACE' has no IP address"
    exit 1
fi

for _ in $(seq 1 6); do
    if kubectl exec backup -n "$NAMESPACE" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${REPORTS_IP}:80" > /dev/null 2>&1; then
        echo "✅ Pod 'backup' can reach 'reports' on port 80"
        exit 0
    fi
    sleep 5
done

echo "❌ Pod 'backup' cannot reach 'reports' on port 80"
exit 1
