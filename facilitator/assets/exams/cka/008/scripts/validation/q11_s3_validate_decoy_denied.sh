#!/bin/bash

set -e

# The probed name carries a trailing dot, making it an absolute FQDN. Both
# resolvers here treat a 4-dot name as relative -- glibc because of ndots:5, and
# busybox wget because it honours the search list (its nslookup does not) -- so a
# wildcard search domain inherited from the host can answer before the cluster
# does. The trailing dot skips the search list entirely.

# Only counts once the archive path works, because 'secrets-api' is unreachable
# from the start -- the seeded default-deny-egress blocks everything. Without
# that precondition an untouched cluster would score here for doing nothing.
#
# This is what catches 'allow all egress' and 'egress to 0.0.0.0/0' as repairs.

NAMESPACE="np-ts-egress"
DECOY_NS="np-ts-egress-decoy"
FQDN="archive.np-ts-egress-store.svc.cluster.local."

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

ALLOWED="no"
for _ in $(seq 1 6); do
    if kubectl exec sync-agent -n "$NAMESPACE" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${FQDN}:80" > /dev/null 2>&1; then
        ALLOWED="yes"
        break
    fi
    sleep 5
done

if [[ "$ALLOWED" != "yes" ]]; then
    echo "❌ 'sync-agent' still cannot reach 'archive', so the fault has not been repaired"
    exit 1
fi

DECOY_IP=$(kubectl get pod secrets-api -n "$DECOY_NS" -o jsonpath='{.status.podIP}')
if [[ -z "$DECOY_IP" ]]; then
    echo "❌ Pod 'secrets-api' in '$DECOY_NS' has no IP address"
    exit 1
fi

if kubectl exec sync-agent -n "$NAMESPACE" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${DECOY_IP}:80" > /dev/null 2>&1; then
    echo "❌ Pod 'sync-agent' can reach '$DECOY_NS', so egress was opened too far"
    exit 1
fi

echo "✅ 'sync-agent' reaches 'archive' and nothing else outside its namespace"
exit 0
