#!/bin/bash

set -e

# 'scanner' is already shut out by the seeded default-deny, so this step is only
# meaningful once the candidate's own policy exists -- otherwise it would score
# on an untouched cluster.

NAMESPACE="np-tiers"
POLICY="api-allow-frontend"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so nothing has been solved yet"
    exit 1
fi

API_IP=$(kubectl get pod api -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$API_IP" ]]; then
    echo "❌ Pod 'api' in '$NAMESPACE' has no IP address"
    exit 1
fi

if kubectl exec scanner -n "$NAMESPACE" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${API_IP}:80" > /dev/null 2>&1; then
    echo "❌ Pod 'scanner' can reach 'api', so the policy is wider than it should be"
    exit 1
fi

echo "✅ Pod 'scanner' is denied access to 'api'"
exit 0
