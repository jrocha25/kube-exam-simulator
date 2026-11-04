#!/bin/bash

set -e

NAMESPACE="np-combined"
PLATFORM_NS="np-combined-platform"
POLICY="ledger-ingress"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so no traffic has been permitted"
    exit 1
fi

LEDGER_IP=$(kubectl get pod ledger -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$LEDGER_IP" ]]; then
    echo "❌ Pod 'ledger' in '$NAMESPACE' has no IP address"
    exit 1
fi

for _ in $(seq 1 6); do
    if kubectl exec collector -n "$PLATFORM_NS" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${LEDGER_IP}:80" > /dev/null 2>&1; then
        echo "✅ Pod 'collector' in '$PLATFORM_NS' can reach 'ledger' on port 80"
        exit 0
    fi
    sleep 5
done

echo "❌ Pod 'collector' in '$PLATFORM_NS' cannot reach 'ledger' on port 80"
exit 1
