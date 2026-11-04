#!/bin/bash

set -e

# Guard first. With no policy at all every Pod can reach every other Pod, so an
# unreachable 'web' only means something once the policy is actually there.

NAMESPACE="np-baseline"
POLICY="default-deny-ingress"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so nothing is being enforced"
    exit 1
fi

WEB_IP=$(kubectl get pod web -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$WEB_IP" ]]; then
    echo "❌ Pod 'web' in '$NAMESPACE' has no IP address"
    exit 1
fi

if kubectl exec client -n "$NAMESPACE" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${WEB_IP}:80" > /dev/null 2>&1; then
    echo "❌ Pod 'client' can still reach 'web' on port 80"
    exit 1
fi

echo "✅ Pod 'client' is denied access to 'web'"
exit 0
