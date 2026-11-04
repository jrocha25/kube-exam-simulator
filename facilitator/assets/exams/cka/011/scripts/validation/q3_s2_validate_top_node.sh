#!/bin/bash
set -e

# Every Ready node has to report, not just one: a metrics-server that can reach
# some kubelets and not others is the usual half-fixed state.

EXPECTED=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')
if [[ -z "$EXPECTED" || "$EXPECTED" == "0" ]]; then
    echo "❌ No Ready nodes found; the cluster is not healthy"
    exit 1
fi

for _ in $(seq 1 12); do
    OUT=$(kubectl top node --no-headers 2>&1 || true)
    ROWS=$(grep -cE '^[^[:space:]]+[[:space:]]+[0-9]+m?' <<<"$OUT" 2>/dev/null || true)
    [[ "${ROWS:-0}" -ge "$EXPECTED" ]] && break
    sleep 5
done

if [[ "${ROWS:-0}" -lt "$EXPECTED" ]]; then
    echo "❌ 'kubectl top node' reported ${ROWS:-0} node(s), expected ${EXPECTED}"
    echo "   Output: $(head -c 300 <<<"$OUT" | tr '\n' ' ')"
    exit 1
fi

# A row with an unknown value is not usage.
if grep -qi 'unknown\|<none>' <<<"$OUT"; then
    echo "❌ 'kubectl top node' reported a node with no usage value"
    echo "   Output: $(head -c 300 <<<"$OUT" | tr '\n' ' ')"
    exit 1
fi

echo "✅ 'kubectl top node' reports usage for all ${EXPECTED} nodes"
exit 0
