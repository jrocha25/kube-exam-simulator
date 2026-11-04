#!/bin/bash
set -e

NAMESPACE="dns-alias"
ALIAS="ledger.corp.internal"
POD="resolver"

if ! kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ The '$POD' Pod is missing from namespace '$NAMESPACE'"
    exit 1
fi

# The answer has to be the Service's live cluster IP -- read now, not hardcoded.
EXPECTED=$(kubectl get service ledger -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -z "$EXPECTED" ]]; then
    echo "❌ Service 'ledger' has no cluster IP"
    exit 1
fi

# A trailing dot makes the name absolute, so no search domain can answer it.
# CoreDNS needs a moment after a restart; bounded retry.
for _ in $(seq 1 12); do
    OUT=$(kubectl exec -n "$NAMESPACE" "$POD" -- nslookup "${ALIAS}." 2>&1 || true)
    grep -q "$EXPECTED" <<<"$OUT" && break
    sleep 5
done
if ! grep -q "$EXPECTED" <<<"$OUT"; then
    echo "❌ '${ALIAS}' does not resolve to ${EXPECTED} from '$POD'"
    echo "   Last output: $(head -c 300 <<<"$OUT" | tr '\n' ' ')"
    exit 1
fi

echo "✅ '${ALIAS}' resolves to ${EXPECTED} from inside the cluster"
exit 0
