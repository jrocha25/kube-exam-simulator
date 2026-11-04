#!/bin/bash
set -e

CLUSTERROLE="deployment-reader"

if ! kubectl get clusterrole "$CLUSTERROLE" &> /dev/null; then
    echo "❌ ClusterRole '$CLUSTERROLE' not found"
    exit 1
fi

ROLE_JSON=$(kubectl get clusterrole "$CLUSTERROLE" -o json)

MATCHING_RULES=$(echo "$ROLE_JSON" | jq '[.rules // [] | .[]
  | select((.apiGroups // []) | index("apps"))
  | select((.resources // []) | index("deployments"))
  | select((.resources // []) | index("replicasets"))
  | select((.verbs // []) | index("get"))
  | select((.verbs // []) | index("list"))
  | select((.verbs // []) | index("watch"))] | length')

if [[ "$MATCHING_RULES" == "0" ]]; then
    echo "❌ ClusterRole '$CLUSTERROLE' does not grant get, list and watch on deployments and replicasets in the apps API group"
    exit 1
fi

FORBIDDEN=$(echo "$ROLE_JSON" | jq '[.rules // [] | .[] | (.verbs // []) | .[] | select(. == "*" or . == "create" or . == "delete" or . == "update" or . == "patch")] | length')
if [[ "$FORBIDDEN" != "0" ]]; then
    echo "❌ ClusterRole '$CLUSTERROLE' grants write verbs; only get, list and watch are allowed"
    exit 1
fi

echo "✅ ClusterRole '$CLUSTERROLE' grants the required read-only permissions"
exit 0
