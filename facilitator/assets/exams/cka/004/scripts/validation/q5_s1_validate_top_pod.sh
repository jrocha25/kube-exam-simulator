#!/bin/bash
set -e

ANSWER_FILE="/tmp/exam/q5/top-pod.txt"
EXPECTED_NAMESPACE="loadgen"

if [[ ! -f "$ANSWER_FILE" ]]; then
    echo "❌ '$ANSWER_FILE' not found"
    exit 1
fi

CONTENT=$(tr -d '[:space:]' < "$ANSWER_FILE")
if [[ -z "$CONTENT" ]]; then
    echo "❌ '$ANSWER_FILE' is empty"
    exit 1
fi

if [[ "$CONTENT" != */* ]]; then
    echo "❌ '$ANSWER_FILE' must contain the answer as 'namespace/pod_name' (got: '$CONTENT')"
    exit 1
fi

ANSWER_NS=${CONTENT%%/*}
ANSWER_POD=${CONTENT#*/}

if ! kubectl get pod "$ANSWER_POD" -n "$ANSWER_NS" &> /dev/null; then
    echo "❌ Pod '$ANSWER_NS/$ANSWER_POD' does not exist"
    exit 1
fi

# Measure rather than assume. metrics-server needs a moment after an evaluation
# starts, so the reading is retried before the answer is judged wrong.
TOP=""
for _ in $(seq 1 12); do
    TOP=$(kubectl top pod -A --no-headers --sort-by=cpu 2>/dev/null | head -1 || true)
    [[ -n "$TOP" ]] && break
    sleep 5
done

if [[ -n "$TOP" ]]; then
    EXPECTED_NS=$(awk '{print $1}' <<< "$TOP")
    EXPECTED_POD=$(awk '{print $2}' <<< "$TOP")
    if [[ "$ANSWER_NS" == "$EXPECTED_NS" && "$ANSWER_POD" == "$EXPECTED_POD" ]]; then
        echo "✅ '$ANSWER_FILE' names the Pod consuming the most CPU: $EXPECTED_NS/$EXPECTED_POD"
        exit 0
    fi

    # The planted CPU bound workload is the same true answer, so a momentary
    # wobble in the live ordering must not fail a correct answer.
    HOG_LABEL=$(kubectl get pod "$ANSWER_POD" -n "$ANSWER_NS" -o jsonpath='{.metadata.labels.app}' 2>/dev/null || true)
    if [[ "$ANSWER_NS" == "$EXPECTED_NAMESPACE" && "$HOG_LABEL" == "cpu-hog" ]]; then
        echo "✅ '$ANSWER_FILE' names the Pod consuming the most CPU"
        exit 0
    fi

    echo "❌ '$ANSWER_FILE' names '$CONTENT', but the busiest Pod is '$EXPECTED_NS/$EXPECTED_POD'"
    exit 1
fi

# metrics unreadable: fall back to the planted workload rather than failing an
# answer the candidate had no way to check either.
echo "⚠️  The metrics API returned nothing; falling back to the known CPU bound workload"
if [[ "$ANSWER_NS" != "$EXPECTED_NAMESPACE" ]]; then
    echo "❌ The Pod consuming the most CPU is not in namespace '$ANSWER_NS'"
    exit 1
fi

LABEL=$(kubectl get pod "$ANSWER_POD" -n "$ANSWER_NS" -o jsonpath='{.metadata.labels.app}')
if [[ "$LABEL" != "cpu-hog" ]]; then
    echo "❌ Pod '$ANSWER_NS/$ANSWER_POD' is not the Pod consuming the most CPU"
    exit 1
fi

echo "✅ '$ANSWER_FILE' names the Pod consuming the most CPU"
exit 0
