#!/bin/bash
set -e

ANSWER_FILE="/tmp/exam/q5/top-node.txt"
NAMESPACE="loadgen"

if [[ ! -f "$ANSWER_FILE" ]]; then
    echo "❌ '$ANSWER_FILE' not found"
    exit 1
fi

CONTENT=$(tr -d '[:space:]' < "$ANSWER_FILE")
if [[ -z "$CONTENT" ]]; then
    echo "❌ '$ANSWER_FILE' is empty"
    exit 1
fi

# Resolve the busiest Pod from live metrics, so the node is derived from a
# measurement rather than from a fixed position in a list.
TOP=""
for _ in $(seq 1 12); do
    TOP=$(kubectl top pod -A --no-headers --sort-by=cpu 2>/dev/null | head -1 || true)
    [[ -n "$TOP" ]] && break
    sleep 5
done

if [[ -n "$TOP" ]]; then
    TOP_NS=$(awk '{print $1}' <<< "$TOP")
    TOP_POD=$(awk '{print $2}' <<< "$TOP")
else
    echo "⚠️  The metrics API returned nothing; falling back to the known CPU bound workload"
    TOP_NS="$NAMESPACE"
    TOP_POD=$(kubectl get pods -n "$NAMESPACE" -l app=cpu-hog \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi

if [[ -z "$TOP_POD" ]]; then
    echo "❌ Could not determine the busiest Pod, cannot verify the answer"
    exit 1
fi

EXPECTED_NODE=$(kubectl get pod "$TOP_POD" -n "$TOP_NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
if [[ -z "$EXPECTED_NODE" ]]; then
    echo "❌ Pod '$TOP_NS/$TOP_POD' is not scheduled, cannot verify the answer"
    exit 1
fi

if [[ "$CONTENT" != "$EXPECTED_NODE" ]]; then
    echo "❌ Incorrect node name. Expected '$EXPECTED_NODE', got '$CONTENT'"
    exit 1
fi

echo "✅ '$ANSWER_FILE' names the node running the busiest Pod"
exit 0
