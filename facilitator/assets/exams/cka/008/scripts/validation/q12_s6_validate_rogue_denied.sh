#!/bin/bash

set -e

# 'rogue' shares the clients namespace with 'ingress-gw', so a policy that admits
# the namespace instead of the Pod label lets it through.

NAMESPACE="np-design"
CLIENT_NS="np-design-clients"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" -o json | jq '[.items[]] | length')
if [[ "$COUNT" == "0" ]]; then
    echo "❌ No NetworkPolicy exists in '$NAMESPACE', so nothing has been designed yet"
    exit 1
fi

WEB_IP=$(kubectl get pod web -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$WEB_IP" ]]; then
    echo "❌ Pod 'web' in '$NAMESPACE' has no IP address"
    exit 1
fi

if kubectl exec rogue -n "$CLIENT_NS" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${WEB_IP}:80" > /dev/null 2>&1; then
    echo "❌ Pod 'rogue' can reach the web tier; the rule admits the namespace rather than the Pod"
    exit 1
fi

echo "✅ Pod 'rogue' is denied access to the web tier"
exit 0
