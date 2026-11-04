#!/bin/bash
set -e

NAMESPACE="helm-apps"
RELEASE="webstack"

RELEASE_JSON=$(helm list -n "$NAMESPACE" -o json)

FOUND=$(echo "$RELEASE_JSON" | jq --arg r "$RELEASE" '[.[] | select(.name == $r)] | length')
if [[ "$FOUND" == "0" ]]; then
    echo "❌ Helm release '$RELEASE' not found in namespace '$NAMESPACE'"
    exit 1
fi

STATUS=$(echo "$RELEASE_JSON" | jq -r --arg r "$RELEASE" '.[] | select(.name == $r) | .status')
if [[ "$STATUS" != "deployed" ]]; then
    echo "❌ Helm release '$RELEASE' has status '$STATUS', expected 'deployed'"
    exit 1
fi

CHART=$(echo "$RELEASE_JSON" | jq -r --arg r "$RELEASE" '.[] | select(.name == $r) | .chart')
if [[ "$CHART" != "webstack-0.1.0" ]]; then
    echo "❌ Helm release '$RELEASE' uses chart '$CHART', expected 'webstack-0.1.0'"
    exit 1
fi

echo "✅ Helm release '$RELEASE' is deployed in namespace '$NAMESPACE'"
exit 0
