#!/bin/bash
set -e

NAMESPACE="helm-pub"
RELEASE="podinfo"

VALUES=$(helm get values "$RELEASE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$VALUES" || "$VALUES" == "null" ]]; then
    echo "❌ Release '$RELEASE' has no user supplied values"
    exit 1
fi

REPLICAS=$(echo "$VALUES" | jq -r '.replicaCount // empty')
if [[ "$REPLICAS" != "4" ]]; then
    echo "❌ Expected 'replicaCount' to be '4', got '${REPLICAS:-<none>}'"
    exit 1
fi

MESSAGE=$(echo "$VALUES" | jq -r '.ui.message // empty')
if [[ "$MESSAGE" != "helioscale edge" ]]; then
    echo "❌ Expected 'ui.message' to be 'helioscale edge', got '${MESSAGE:-<none>}'"
    exit 1
fi

echo "✅ Release '$RELEASE' keeps both overridden values after the upgrade"
exit 0
