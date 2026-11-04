#!/bin/bash

set -e

# Probed by Pod IP rather than by name, so this stays a statement about the
# egress rules and not about whether DNS happens to be working.

NAMESPACE="np-egress"
POLICY="orders-egress"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so nothing has been solved yet"
    exit 1
fi

REPORTS_IP=$(kubectl get pod reports -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$REPORTS_IP" ]]; then
    echo "❌ Pod 'reports' in '$NAMESPACE' has no IP address"
    exit 1
fi

if kubectl exec orders -n "$NAMESPACE" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${REPORTS_IP}:80" > /dev/null 2>&1; then
    echo "❌ Pod 'orders' can still reach 'reports', so the egress rules are too wide"
    exit 1
fi

echo "✅ Pod 'orders' is denied egress to 'reports'"
exit 0
