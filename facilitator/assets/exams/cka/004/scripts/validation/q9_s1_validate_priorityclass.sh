#!/bin/bash
set -e

PRIORITY_CLASS="edge-critical"
EXPECTED_VALUE="44999"

if ! kubectl get priorityclass "$PRIORITY_CLASS" &> /dev/null; then
    echo "❌ PriorityClass '$PRIORITY_CLASS' not found"
    exit 1
fi

VALUE=$(kubectl get priorityclass "$PRIORITY_CLASS" -o jsonpath='{.value}')
if [[ "$VALUE" != "$EXPECTED_VALUE" ]]; then
    echo "❌ Incorrect value. Expected '$EXPECTED_VALUE', got '$VALUE'"
    exit 1
fi

GLOBAL_DEFAULT=$(kubectl get priorityclass "$PRIORITY_CLASS" -o json | jq -r '.globalDefault // false')
if [[ "$GLOBAL_DEFAULT" != "false" ]]; then
    echo "❌ PriorityClass '$PRIORITY_CLASS' must not be the global default"
    exit 1
fi

echo "✅ PriorityClass '$PRIORITY_CLASS' has the value $EXPECTED_VALUE and is not the global default"
exit 0
