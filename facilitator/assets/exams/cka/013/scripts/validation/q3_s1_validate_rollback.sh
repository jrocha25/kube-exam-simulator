#!/bin/bash
set -e

NAMESPACE="helm-tide"
RELEASE="tidewatch"

HISTORY=$(helm history "$RELEASE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$HISTORY" ]]; then
    echo "❌ Release '$RELEASE' not found in namespace '$NAMESPACE'"
    exit 1
fi

# The rollback has to come after the broken revision 2 and has to name revision 1.
ROLLBACK=$(echo "$HISTORY" | jq -r '[.[] | select(.revision > 2 and .description == "Rollback to 1")] | first | .revision // empty')
if [[ -z "$ROLLBACK" ]]; then
    echo "❌ The history shows no rollback to revision 1 after the broken upgrade"
    exit 1
fi

echo "✅ Revision $ROLLBACK rolled '$RELEASE' back to revision 1"
exit 0
