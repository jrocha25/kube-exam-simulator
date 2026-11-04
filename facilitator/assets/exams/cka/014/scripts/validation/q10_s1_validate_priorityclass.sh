#!/bin/bash
set -e

PC="berth-urgent"

ALL=$(kubectl get priorityclasses -o json)
VALUE=$(echo "$ALL" | jq -r --arg pc "$PC" '.items[] | select(.metadata.name == $pc) | .value')
if [[ -z "$VALUE" ]]; then
    echo "❌ PriorityClass '$PC' not found"
    exit 1
fi

# Recomputed live: the highest user-defined class, i.e. everything but the
# built-in system-* classes and the candidate's own.
HIGHEST=$(echo "$ALL" | jq -r --arg pc "$PC" '[.items[]
    | select((.metadata.name | startswith("system-")) | not)
    | select(.metadata.name != $pc) | .value] | max')
EXPECTED=$((HIGHEST - 1))
if [[ "$VALUE" != "$EXPECTED" ]]; then
    echo "❌ '$PC' has value $VALUE; the highest user-defined class is $HIGHEST, so it should be $EXPECTED"
    exit 1
fi

if [[ "$(echo "$ALL" | jq -r --arg pc "$PC" '.items[] | select(.metadata.name == $pc) | .globalDefault // false')" == "true" ]]; then
    echo "❌ '$PC' must not be the global default"
    exit 1
fi

echo "✅ '$PC' has value $EXPECTED, one below the highest user-defined class"
exit 0
