#!/bin/bash
set -e

RELEASE="berthwatch"
NAMESPACE="helm-berth"

STATUS_JSON=$(helm status "$RELEASE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$STATUS_JSON" ]]; then
    echo "❌ Helm release '$RELEASE' not found in namespace '$NAMESPACE'"
    exit 1
fi

STATUS=$(echo "$STATUS_JSON" | jq -r '.info.status')
if [[ "$STATUS" != "deployed" ]]; then
    echo "❌ Release '$RELEASE' is '$STATUS', not deployed"
    exit 1
fi

CHART=$(helm list -n "$NAMESPACE" -o json | jq -r --arg r "$RELEASE" '.[] | select(.name == $r) | .chart')
if [[ "$CHART" != "berthwatch-0.7.2" ]]; then
    echo "❌ Release '$RELEASE' runs chart '$CHART', expected berthwatch-0.7.2"
    exit 1
fi

VALUES=$(helm get values "$RELEASE" -n "$NAMESPACE" -a -o json)
if [[ "$(echo "$VALUES" | jq -r '.replicaCount')" != "2" ]]; then
    echo "❌ Release '$RELEASE' does not set replicaCount to 2"
    exit 1
fi
if [[ "$(echo "$VALUES" | jq -r '.crds.install')" != "false" ]]; then
    echo "❌ Release '$RELEASE' still has the chart install its CRD"
    exit 1
fi

echo "✅ Release '$RELEASE' is deployed from berthwatch-0.7.2 with 2 replicas and no CRD"
exit 0
