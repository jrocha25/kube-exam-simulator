#!/bin/bash
set -e

NAMESPACE="compliance"
NAME="audit-keys"
EXPECTED="r7-audit-2026"

JSON=$(kubectl get secret "$NAME" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Secret '$NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

TYPE=$(echo "$JSON" | jq -r '.type')
if [[ "$TYPE" != "Opaque" ]]; then
    echo "❌ '$NAME' is of type '$TYPE', expected 'Opaque'"
    exit 1
fi

VALUE=$(echo "$JSON" | jq -r '.data.SIGNING_KEY // empty' | base64 -d 2>/dev/null || true)
if [[ "$VALUE" != "$EXPECTED" ]]; then
    echo "❌ '$NAME' holds SIGNING_KEY='${VALUE:-<missing>}', expected '$EXPECTED'"
    exit 1
fi

KEYS=$(echo "$JSON" | jq -r '[.data | keys[]] | sort | join(",")')
if [[ "$KEYS" != "SIGNING_KEY" ]]; then
    echo "❌ '$NAME' holds keys '$KEYS', expected exactly 'SIGNING_KEY'"
    exit 1
fi

IMMUTABLE=$(echo "$JSON" | jq -r '.immutable // false')
if [[ "$IMMUTABLE" != "true" ]]; then
    echo "❌ '$NAME' is not marked immutable"
    exit 1
fi

if kubectl patch secret "$NAME" -n "$NAMESPACE" \
        -p '{"stringData":{"SIGNING_KEY":"tampered"}}' >/dev/null 2>&1; then
    echo "❌ '$NAME' accepted an update to its data -- it is not really immutable"
    exit 1
fi

echo "✅ Secret '$NAME' holds the required data and rejects updates"
exit 0
