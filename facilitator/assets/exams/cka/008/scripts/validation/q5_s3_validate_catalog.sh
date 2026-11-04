#!/bin/bash

set -e

# The probed name carries a trailing dot, making it an absolute FQDN. Both
# resolvers here treat a 4-dot name as relative -- glibc because of ndots:5, and
# busybox wget because it honours the search list (its nslookup does not) -- so a
# wildcard search domain inherited from the host can answer before the cluster
# does. The trailing dot skips the search list entirely.

NAMESPACE="np-egress"
POLICY="orders-egress"
FQDN="catalog.np-egress.svc.cluster.local."

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so egress has not been restricted at all"
    exit 1
fi

for _ in $(seq 1 6); do
    if kubectl exec orders -n "$NAMESPACE" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${FQDN}:80" > /dev/null 2>&1; then
        echo "✅ Pod 'orders' can reach 'catalog' by name on port 80"
        exit 0
    fi
    sleep 5
done

echo "❌ Pod 'orders' cannot reach 'catalog' at '$FQDN' on port 80"
exit 1
