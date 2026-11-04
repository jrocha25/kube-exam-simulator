#!/bin/bash

set -e

# Right Pod label, wrong namespace. A policy that lists namespaceSelector and
# podSelector as two separate 'from' entries lets this through -- that is the
# OR-versus-AND trap this question exists for.

NAMESPACE="np-combined"
EDGE_NS="np-combined-edge"
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

if kubectl exec collector -n "$EDGE_NS" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${LEDGER_IP}:80" > /dev/null 2>&1; then
    echo "❌ Pod 'collector' in the unlabelled namespace '$EDGE_NS' can reach 'ledger'"
    exit 1
fi

echo "✅ Pod 'collector' in '$EDGE_NS' is denied access to 'ledger'"
exit 0
