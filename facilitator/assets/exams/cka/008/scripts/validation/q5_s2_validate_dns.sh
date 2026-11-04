#!/bin/bash

set -e

# The probed name carries a trailing dot, making it an absolute FQDN. Both
# resolvers here treat a 4-dot name as relative -- glibc because of ndots:5, and
# busybox wget because it honours the search list (its nslookup does not) -- so a
# wildcard search domain inherited from the host can answer before the cluster
# does. The trailing dot skips the search list entirely.

# Grepping the lookup output for the Service's real ClusterIP is what makes this
# unfakeable -- an 'echo' of the name alone would not contain an address the
# candidate has no way to guess.

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

CLUSTER_IP=$(kubectl get service catalog -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
if [[ -z "$CLUSTER_IP" ]]; then
    echo "❌ Service 'catalog' in '$NAMESPACE' has no ClusterIP"
    exit 1
fi

for _ in $(seq 1 6); do
    OUTPUT=$(kubectl exec orders -n "$NAMESPACE" --request-timeout=60s -- \
        nslookup "$FQDN" 2> /dev/null || true)
    if echo "$OUTPUT" | grep -q "$CLUSTER_IP"; then
        echo "✅ Pod 'orders' resolves '$FQDN' to $CLUSTER_IP"
        exit 0
    fi
    sleep 5
done

echo "❌ Pod 'orders' cannot resolve '$FQDN'"
exit 1
