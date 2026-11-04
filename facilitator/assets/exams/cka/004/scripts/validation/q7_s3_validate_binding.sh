#!/bin/bash
set -e

NAMESPACE="delivery"
BINDING="pipeline-binding"
CLUSTER_ROLE="deploy-manager"
SA_NAME="pipeline-bot"

if ! kubectl get rolebinding "$BINDING" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ RoleBinding '$BINDING' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get rolebinding "$BINDING" -n "$NAMESPACE" -o json)

ROLE_KIND=$(echo "$SPEC" | jq -r '.roleRef.kind // empty')
ROLE_NAME=$(echo "$SPEC" | jq -r '.roleRef.name // empty')
if [[ "$ROLE_KIND" != "ClusterRole" ]] || [[ "$ROLE_NAME" != "$CLUSTER_ROLE" ]]; then
    echo "❌ RoleBinding '$BINDING' must reference the ClusterRole '$CLUSTER_ROLE' (got: '$ROLE_KIND/$ROLE_NAME')"
    exit 1
fi

SUBJECTS=$(echo "$SPEC" | jq --arg ns "$NAMESPACE" --arg sa "$SA_NAME" '[.subjects // [] | .[]
    | select(.kind == "ServiceAccount" and .name == $sa and .namespace == $ns)] | length')
if [[ "$SUBJECTS" == "0" ]]; then
    echo "❌ RoleBinding '$BINDING' does not bind the ServiceAccount '$NAMESPACE/$SA_NAME'"
    exit 1
fi

echo "✅ RoleBinding '$BINDING' binds ClusterRole '$CLUSTER_ROLE' to '$NAMESPACE/$SA_NAME'"
exit 0
