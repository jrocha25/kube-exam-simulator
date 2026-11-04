#!/bin/bash

set -e

# The probed name carries a trailing dot, making it an absolute FQDN. Both
# resolvers here treat a 4-dot name as relative -- glibc because of ndots:5, and
# busybox wget because it honours the search list (its nslookup does not) -- so a
# wildcard search domain inherited from the host can answer before the cluster
# does. The trailing dot skips the search list entirely.

NAMESPACE="np-design"
FQDN="db.np-design.svc.cluster.local."

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" -o json | jq '[.items[]] | length')
if [[ "$COUNT" == "0" ]]; then
    echo "❌ No NetworkPolicy exists in '$NAMESPACE', so nothing has been designed yet"
    exit 1
fi

for _ in $(seq 1 6); do
    if kubectl exec api -n "$NAMESPACE" --request-timeout=60s -- \
            timeout 5 bash -c "echo > /dev/tcp/${FQDN}/5432" > /dev/null 2>&1; then
        echo "✅ The api tier can reach the db tier on port 5432"
        exit 0
    fi
    sleep 5
done

echo "❌ The api tier cannot reach the db tier at '$FQDN' on port 5432"
exit 1
