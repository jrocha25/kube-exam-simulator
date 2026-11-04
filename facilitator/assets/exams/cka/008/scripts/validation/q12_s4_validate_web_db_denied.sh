#!/bin/bash

set -e

# By IP, so a denial here is a statement about the policy rather than about DNS.

NAMESPACE="np-design"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" -o json | jq '[.items[]] | length')
if [[ "$COUNT" == "0" ]]; then
    echo "❌ No NetworkPolicy exists in '$NAMESPACE', so nothing has been designed yet"
    exit 1
fi

DB_IP=$(kubectl get pod db -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$DB_IP" ]]; then
    echo "❌ Pod 'db' in '$NAMESPACE' has no IP address"
    exit 1
fi

if kubectl exec web -n "$NAMESPACE" --request-timeout=60s -- \
        timeout 5 bash -c "echo > /dev/tcp/${DB_IP}/5432" > /dev/null 2>&1; then
    echo "❌ The web tier can reach the db tier directly, skipping the api tier"
    exit 1
fi

echo "✅ The web tier is denied direct access to the db tier"
exit 0
