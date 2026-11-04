#!/bin/bash
set -e

NAMESPACE="helm-broken"
RELEASE="orderbook"

INFO=$(helm list -n "$NAMESPACE" -o json 2>/dev/null | jq -r --arg r "$RELEASE" '[.[] | select(.name==$r)][0] // empty')
if [[ -z "$INFO" ]]; then
    echo "❌ Helm release '$RELEASE' not found in namespace '$NAMESPACE'"
    exit 1
fi

STATUS=$(echo "$INFO" | jq -r '.status')
if [[ "$STATUS" != "deployed" ]]; then
    echo "❌ Release '$RELEASE' is '$STATUS', expected 'deployed'"
    exit 1
fi

CHART=$(echo "$INFO" | jq -r '.chart')
if [[ "$CHART" != orderbook-* ]]; then
    echo "❌ Release '$RELEASE' was installed from chart '$CHART', expected the orderbook chart"
    exit 1
fi

echo "✅ Release '$RELEASE' is deployed from '$CHART'"
exit 0
