#!/bin/bash
set -e

NAMESPACE="insight"
FILE="/tmp/exam/q3/restarts.txt"

if [[ ! -f "$FILE" ]]; then
    echo "❌ '$FILE' does not exist"
    exit 1
fi

# Recompute the answer now rather than hardcoding it: restart counts keep rising
# during the exam, but the Pod holding the highest count never changes.
EXPECTED=$(kubectl get pods -n "$NAMESPACE" -o json \
    | jq -r '[.items[] | {name: .metadata.name, r: ([.status.containerStatuses[]?.restartCount] | add // 0)}]
             | max_by(.r) | .name')

ACTUAL=$(tr -d '[:space:]' < "$FILE")

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    echo "❌ '$FILE' contains '${ACTUAL:-<empty>}', expected '$EXPECTED'"
    exit 1
fi

echo "✅ '$FILE' names the most frequently restarted Pod: $EXPECTED"
exit 0
