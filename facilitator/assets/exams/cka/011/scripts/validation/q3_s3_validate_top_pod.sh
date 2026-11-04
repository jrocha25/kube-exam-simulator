#!/bin/bash
set -e

NAMESPACE="ops-metrics"

for _ in $(seq 1 12); do
    OUT=$(kubectl top pod -n "$NAMESPACE" --containers --no-headers 2>&1 || true)
    FEED=$(grep -cE '[[:space:]]feed[[:space:]]' <<<"$OUT" 2>/dev/null || true)
    RELAY=$(grep -cE '[[:space:]]relay[[:space:]]' <<<"$OUT" 2>/dev/null || true)
    [[ "${FEED:-0}" -ge 2 && "${RELAY:-0}" -ge 2 ]] && break
    sleep 5
done

if [[ "${FEED:-0}" -lt 2 || "${RELAY:-0}" -lt 2 ]]; then
    echo "❌ 'kubectl top pod -n ${NAMESPACE} --containers' did not report both containers of both radar-feed Pods"
    echo "   (found ${FEED:-0} 'feed' and ${RELAY:-0} 'relay' rows, expected 2 of each)"
    echo "   Output: $(head -c 400 <<<"$OUT" | tr '\n' ' ')"
    exit 1
fi

echo "✅ Per-container usage is reported for both containers of every radar-feed Pod"
exit 0
