#!/bin/bash
set -e

NAMESPACE="ts-cargo"
DEPLOYMENT="cargo-api"

REF=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -c '[.spec.template.spec.containers[0].env[]? | select(.name == "API_TOKEN") | .valueFrom.secretKeyRef | {name, key}] | first // empty')
if [[ "$REF" != '{"name":"relay-secrets","key":"api-token"}' ]]; then
    echo "❌ API_TOKEN is not read from the key that exists in relay-secrets (got ${REF:-nothing})"
    exit 1
fi

echo "✅ API_TOKEN comes from relay-secrets"
exit 0
