#!/bin/bash
set -e

# Graded on the text in the file, not on the command that produced it: the
# expected set is recomputed from the live cluster here, compared as a set, and
# whitespace and CR are tolerated. kind's node names cannot be guessed, so a
# correct file can only have come from the cluster.

FILE="/tmp/exam/q13/ready-nodes.txt"

if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' is missing or empty"
    exit 1
fi

EXPECTED=$(kubectl get nodes -o json 2>/dev/null \
    | jq -r '.items[] | select([.status.conditions[] | select(.type == "Ready" and .status == "True")] | length > 0) | .metadata.name' \
    | sort -u)
if [[ -z "$EXPECTED" ]]; then
    echo "❌ Could not read the list of Ready nodes from the cluster"
    exit 1
fi

GOT=$(sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$FILE" | grep -v '^$' | sort -u)

if [[ "$GOT" != "$EXPECTED" ]]; then
    echo "❌ '$FILE' does not list exactly the Ready nodes"
    echo "   Expected: $(tr '\n' ' ' <<<"$EXPECTED")"
    echo "   Found:    $(tr '\n' ' ' <<<"$GOT")"
    echo "   One name per line, nothing else -- no column headers and no status column."
    exit 1
fi

echo "✅ '$FILE' lists exactly the Ready nodes"
exit 0
