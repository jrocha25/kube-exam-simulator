#!/bin/bash

set -e

# 'auditor' reaches 'vault' on an untouched cluster too -- nothing is being
# enforced, which is the whole fault. So the policy has to be selecting the Pod
# before this reachability means the access was deliberately granted.

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

POD_LABELS=$(kubectl get pod vault -n "$NAMESPACE" -o json | jq -c '.metadata.labels // {}')
SELECTS=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json \
    | jq --argjson labels "$POD_LABELS" '
        (.spec.podSelector.matchLabels // {}) as $sel
        | [$sel | to_entries[] | select($labels[.key] != .value)] | length == 0')

if [[ "$SELECTS" != "true" ]]; then
    echo "❌ '$POLICY' does not select the 'vault' Pod, so nothing is being enforced yet"
    exit 1
fi

VAULT_IP=$(kubectl get pod vault -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$VAULT_IP" ]]; then
    echo "❌ Pod 'vault' in '$NAMESPACE' has no IP address"
    exit 1
fi

for _ in $(seq 1 6); do
    if kubectl exec auditor -n "$NAMESPACE" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${VAULT_IP}:80" > /dev/null 2>&1; then
        echo "✅ Pod 'auditor' keeps its access to 'vault' on port 80"
        exit 0
    fi
    sleep 5
done

echo "❌ Pod 'auditor' has lost its access to 'vault'"
exit 1
