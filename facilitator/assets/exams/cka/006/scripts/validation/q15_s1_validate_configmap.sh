#!/bin/bash
set -e

NAMESPACE="compliance"
NAME="audit-config"

JSON=$(kubectl get configmap "$NAME" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ ConfigMap '$NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

TLS=$(echo "$JSON" | jq -r '.data.MIN_TLS_VERSION // empty')
MODE=$(echo "$JSON" | jq -r '.data.AUDIT_MODE // empty')

if [[ "$TLS" != "1.2" ]]; then
    echo "❌ MIN_TLS_VERSION is '${TLS:-<missing>}', expected '1.2'"
    exit 1
fi
if [[ "$MODE" != "enabled" ]]; then
    echo "❌ AUDIT_MODE is '${MODE:-<missing>}', expected 'enabled'"
    exit 1
fi

KEYS=$(echo "$JSON" | jq -r '[.data | keys[]] | sort | join(",")')
if [[ "$KEYS" != "AUDIT_MODE,MIN_TLS_VERSION" ]]; then
    echo "❌ '$NAME' holds keys '$KEYS', expected exactly 'AUDIT_MODE,MIN_TLS_VERSION'"
    exit 1
fi

IMMUTABLE=$(echo "$JSON" | jq -r '.immutable // false')
if [[ "$IMMUTABLE" != "true" ]]; then
    echo "❌ '$NAME' is not marked immutable"
    exit 1
fi

# The field being set is the claim; prove the API server actually enforces it.
if kubectl patch configmap "$NAME" -n "$NAMESPACE" \
        -p '{"data":{"AUDIT_MODE":"disabled"}}' >/dev/null 2>&1; then
    echo "❌ '$NAME' accepted an update to its data -- it is not really immutable"
    exit 1
fi

echo "✅ ConfigMap '$NAME' holds the required data and rejects updates"
exit 0
