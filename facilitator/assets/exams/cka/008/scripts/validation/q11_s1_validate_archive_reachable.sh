#!/bin/bash

set -e

# The probed name carries a trailing dot, making it an absolute FQDN. Both
# resolvers here treat a 4-dot name as relative -- glibc because of ndots:5, and
# busybox wget because it honours the search list (its nslookup does not) -- so a
# wildcard search domain inherited from the host can answer before the cluster
# does. The trailing dot skips the search list entirely.

# Probed by name, so this covers the DNS half of the answer as well: with the
# seeded default-deny-egress in place the lookup never leaves the Pod, and no
# amount of correctness on the archive side changes that.

NAMESPACE="np-ts-egress"
FQDN="archive.np-ts-egress-store.svc.cluster.local."

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

for _ in $(seq 1 6); do
    if kubectl exec sync-agent -n "$NAMESPACE" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${FQDN}:80" > /dev/null 2>&1; then
        echo "✅ Pod 'sync-agent' can reach 'archive' at '$FQDN'"
        exit 0
    fi
    sleep 5
done

echo "❌ Pod 'sync-agent' still cannot reach 'archive' at '$FQDN'"
exit 1
