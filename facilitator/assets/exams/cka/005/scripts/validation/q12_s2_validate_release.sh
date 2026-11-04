#!/bin/bash
set -e

NAMESPACE="helm-pub"
RELEASE="podinfo"

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

REVISION=$(echo "$INFO" | jq -r '.revision')
if [[ "$REVISION" -lt 2 ]]; then
    echo "❌ Release '$RELEASE' is at revision '$REVISION'; it was never upgraded"
    exit 1
fi

CHART=$(echo "$INFO" | jq -r '.chart')
if [[ "$CHART" != podinfo-* ]]; then
    echo "❌ Release '$RELEASE' was installed from chart '$CHART', expected the podinfo chart"
    exit 1
fi

echo "✅ Release '$RELEASE' is deployed at revision $REVISION from '$CHART'"
exit 0
