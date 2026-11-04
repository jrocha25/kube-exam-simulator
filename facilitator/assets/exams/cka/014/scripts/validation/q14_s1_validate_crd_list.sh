#!/bin/bash
set -e

FILE=/tmp/exam/q14/tide-crds.txt
GROUP="tides.harbor.io"

if [[ ! -s "$FILE" ]]; then
    echo "❌ $FILE does not exist or is empty"
    exit 1
fi

EXPECTED=$(kubectl get crd -o json | jq -r --arg g "$GROUP" '.items[] | select(.spec.group == $g) | .metadata.name' | sort)
ALL=$(kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# The default output format: one CRD per line, name first, then CREATED AT.
LISTED=$(awk 'NF && $1 != "NAME" {print $1}' "$FILE" | sort)
if [[ "$LISTED" != "$EXPECTED" ]]; then
    echo "❌ $FILE lists '$(echo $LISTED)'; the CRDs of $GROUP are '$(echo $EXPECTED)'"
    exit 1
fi

if ! awk 'NF && $1 != "NAME"' "$FILE" | grep -Eq '[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
    echo "❌ $FILE is not in kubectl's default output format (no CREATED AT column)"
    exit 1
fi

echo "✅ $FILE lists exactly the CRDs of $GROUP"
exit 0
