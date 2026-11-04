#!/bin/bash

set -e

# The probed name carries a trailing dot, making it an absolute FQDN. Both
# resolvers here treat a 4-dot name as relative -- glibc because of ndots:5, and
# busybox wget because it honours the search list (its nslookup does not) -- so a
# wildcard search domain inherited from the host can answer before the cluster
# does. The trailing dot skips the search list entirely.

# 'web' is an nginx Pod: no wget, no curl, but Debian bash, so /dev/tcp is the
# probe. Addressed by name, which means this also proves the web tier's egress
# rules let its DNS queries out.

NAMESPACE="np-design"
FQDN="api.np-design.svc.cluster.local."

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
    if kubectl exec web -n "$NAMESPACE" --request-timeout=60s -- \
            timeout 5 bash -c "echo > /dev/tcp/${FQDN}/8080" > /dev/null 2>&1; then
        echo "✅ The web tier can reach the api tier on port 8080"
        exit 0
    fi
    sleep 5
done

echo "❌ The web tier cannot reach the api tier at '$FQDN' on port 8080"
exit 1
