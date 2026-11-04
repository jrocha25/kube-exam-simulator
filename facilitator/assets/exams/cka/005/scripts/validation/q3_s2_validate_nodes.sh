#!/bin/bash
set -e

FILE="/tmp/exam/q3/nodes.txt"

if [[ ! -f "$FILE" ]]; then
    echo "❌ '$FILE' does not exist"
    exit 1
fi

EXPECTED=$(kubectl get nodes -o json \
    | jq -r '.items[] | "\(.metadata.name) \([.status.addresses[] | select(.type=="InternalIP") | .address][0])"' \
    | sort)

# Column alignment is not the point of the exercise, so runs of whitespace are
# collapsed before comparing; line order still has to match.
ACTUAL=$(sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' -e '/^$/d' "$FILE")

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    echo "❌ '$FILE' does not match the expected node report"
    echo "--- expected ---"
    echo "$EXPECTED"
    echo "--- got ---"
    echo "$ACTUAL"
    exit 1
fi

echo "✅ '$FILE' lists every node with its InternalIP, sorted by name"
exit 0
