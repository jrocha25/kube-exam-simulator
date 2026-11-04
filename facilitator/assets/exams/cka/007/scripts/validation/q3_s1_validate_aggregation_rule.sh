#!/bin/bash
set -e

CLUSTERROLE="monitoring-view"
LABEL_KEY="rbac.ck-x.io/aggregate-to-monitoring"

if ! kubectl get clusterrole "$CLUSTERROLE" &> /dev/null; then
    echo "❌ ClusterRole '$CLUSTERROLE' not found"
    exit 1
fi

SELECTORS=$(kubectl get clusterrole "$CLUSTERROLE" -o json | jq '.aggregationRule.clusterRoleSelectors // []')
if [[ "$(echo "$SELECTORS" | jq 'length')" == "0" ]]; then
    echo "❌ ClusterRole '$CLUSTERROLE' has no aggregationRule; its rules would have to be maintained by hand"
    exit 1
fi

MATCH=$(echo "$SELECTORS" | jq --arg k "$LABEL_KEY" '[.[] | select(.matchLabels[$k] == "true")] | length')
if [[ "$MATCH" == "0" ]]; then
    echo "❌ The aggregationRule of '$CLUSTERROLE' does not select on '$LABEL_KEY: \"true\"'"
    exit 1
fi

echo "✅ ClusterRole '$CLUSTERROLE' aggregates every ClusterRole labelled '$LABEL_KEY=true'"
exit 0
