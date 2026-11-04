#!/bin/bash
set -e

# No trailing dot here, deliberately: the whole point is that the bare name is
# completed from the Pod's own search list.

NAMESPACE="dns-apron"
WX_NAMESPACE="dns-apron-wx"
POD="briefing"
NAME="wx-feed"

if ! kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

EXPECTED=$(kubectl get service "$NAME" -n "$WX_NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -z "$EXPECTED" ]]; then
    echo "❌ Service '$NAME' has no cluster IP in namespace '$WX_NAMESPACE'"
    exit 1
fi

PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is ${PHASE:-absent}, so name resolution cannot be tested"
    exit 1
fi

for _ in $(seq 1 8); do
    OUT=$(kubectl exec -n "$NAMESPACE" "$POD" -- nslookup "$NAME" 2>&1 || true)
    grep -q "$EXPECTED" <<<"$OUT" && break
    sleep 5
done

if ! grep -q "$EXPECTED" <<<"$OUT"; then
    echo "❌ The bare name '${NAME}' does not resolve to ${EXPECTED} from inside '$POD'"
    echo "   Last output: $(head -c 300 <<<"$OUT" | tr '\n' ' ')"
    exit 1
fi

echo "✅ The short name '${NAME}' resolves to the Service in '${WX_NAMESPACE}'"
exit 0
