#!/bin/bash

set -e

# The dev namespace carries no label, so a namespaceSelector of {} -- which
# matches every namespace, not none -- is what this catches.

NAMESPACE="np-crossns"
DEV_NS="np-crossns-dev"
POLICY="payments-ingress"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so nothing has been solved yet"
    exit 1
fi

PAYMENTS_IP=$(kubectl get pod payments -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$PAYMENTS_IP" ]]; then
    echo "❌ Pod 'payments' in '$NAMESPACE' has no IP address"
    exit 1
fi

if kubectl exec probe -n "$DEV_NS" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${PAYMENTS_IP}:80" > /dev/null 2>&1; then
    echo "❌ Pod 'probe' in the unlabelled namespace '$DEV_NS' can still reach 'payments'"
    exit 1
fi

echo "✅ Pod 'probe' in '$DEV_NS' is denied access to 'payments'"
exit 0
