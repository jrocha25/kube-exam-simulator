#!/bin/bash
set -e

# The count is recomputed now rather than hardcoded. The question asks the
# candidate not to create or delete namespaces afterwards for that reason: the
# file is a statement about the cluster, and the cluster is what it is checked
# against.

FILE="/tmp/exam/q13/ns-count.txt"

if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' is missing or empty"
    exit 1
fi

EXPECTED=$(kubectl get namespaces --no-headers 2>/dev/null | grep -c . || true)
if [[ "${EXPECTED:-0}" -eq 0 ]]; then
    echo "❌ Could not count the namespaces in the cluster"
    exit 1
fi

GOT=$(sed -e 's/\r$//' "$FILE" | tr -d '[:space:]')

if [[ ! "$GOT" =~ ^[0-9]+$ ]]; then
    echo "❌ '$FILE' must hold a single integer, found: $(head -c 120 "$FILE" | tr '\n' ' ')"
    exit 1
fi
if [[ "$GOT" -ne "$EXPECTED" ]]; then
    echo "❌ '$FILE' says ${GOT}, the cluster has ${EXPECTED} namespaces"
    exit 1
fi

echo "✅ '$FILE' holds the current namespace count (${EXPECTED})"
exit 0
