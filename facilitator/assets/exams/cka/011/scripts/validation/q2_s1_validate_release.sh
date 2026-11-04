#!/bin/bash
set -e

NAMESPACE="ops-charts"
RELEASE="beacon"

REL=$(helm list -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r --arg r "$RELEASE" '.[] | select(.name==$r)' || true)
if [[ -z "$REL" ]]; then
    echo "❌ There is no Helm release named '$RELEASE' in namespace '$NAMESPACE'"
    exit 1
fi

STATUS=$(jq -r '.status' <<<"$REL")
REVISION=$(jq -r '.revision' <<<"$REL")

if [[ "$STATUS" != "deployed" ]]; then
    echo "❌ Release '$RELEASE' is in status '$STATUS', expected 'deployed'"
    exit 1
fi
if [[ "$REVISION" != "2" ]]; then
    echo "❌ Release '$RELEASE' is at revision '$REVISION', expected '2' (install, then upgrade)"
    exit 1
fi

echo "✅ Release '$RELEASE' is deployed at revision 2"
exit 0
