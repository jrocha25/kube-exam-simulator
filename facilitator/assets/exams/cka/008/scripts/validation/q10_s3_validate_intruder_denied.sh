#!/bin/bash

set -e

NAMESPACE="np-ts-inert"
POLICY="vault-isolation"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' has been deleted from '$NAMESPACE'"
    exit 1
fi

VAULT_IP=$(kubectl get pod vault -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$VAULT_IP" ]]; then
    echo "❌ Pod 'vault' in '$NAMESPACE' has no IP address"
    exit 1
fi

if kubectl exec intruder -n "$NAMESPACE" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${VAULT_IP}:80" > /dev/null 2>&1; then
    echo "❌ Pod 'intruder' can still reach 'vault', so the policy is still not isolating it"
    exit 1
fi

echo "✅ Pod 'intruder' is denied access to 'vault'"
exit 0
