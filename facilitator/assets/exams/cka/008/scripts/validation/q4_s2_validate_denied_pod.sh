#!/bin/bash

set -e

# Right namespace, wrong Pod label. A policy whose 'from' names only the
# namespace lets this through.

NAMESPACE="np-combined"
PLATFORM_NS="np-combined-platform"
POLICY="ledger-ingress"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so nothing has been solved yet"
    exit 1
fi

LEDGER_IP=$(kubectl get pod ledger -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$LEDGER_IP" ]]; then
    echo "❌ Pod 'ledger' in '$NAMESPACE' has no IP address"
    exit 1
fi

if kubectl exec auditor -n "$PLATFORM_NS" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${LEDGER_IP}:80" > /dev/null 2>&1; then
    echo "❌ Pod 'auditor' in '$PLATFORM_NS' can reach 'ledger', so the Pod label is not being matched"
    exit 1
fi

echo "✅ Pod 'auditor' is denied access to 'ledger'"
exit 0
