#!/bin/bash
set -e

NAMESPACE="ops-rbac"
BINDING="deploy-bot-reader"

if ! kubectl get rolebinding "$BINDING" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ RoleBinding '$BINDING' not found in namespace '$NAMESPACE'"
    exit 1
fi

ROLE_KIND=$(kubectl get rolebinding "$BINDING" -n "$NAMESPACE" -o jsonpath='{.roleRef.kind}')
if [[ "$ROLE_KIND" != "ClusterRole" ]]; then
    echo "❌ RoleBinding '$BINDING' must reference a ClusterRole (got: '$ROLE_KIND')"
    exit 1
fi

ROLE_NAME=$(kubectl get rolebinding "$BINDING" -n "$NAMESPACE" -o jsonpath='{.roleRef.name}')
if [[ "$ROLE_NAME" != "deployment-reader" ]]; then
    echo "❌ RoleBinding '$BINDING' references '$ROLE_NAME' instead of 'deployment-reader'"
    exit 1
fi

SUBJECT=$(kubectl get rolebinding "$BINDING" -n "$NAMESPACE" -o json | jq '[.subjects // [] | .[] | select(.kind == "ServiceAccount" and .name == "deploy-bot" and .namespace == "ops-rbac")] | length')
if [[ "$SUBJECT" == "0" ]]; then
    echo "❌ RoleBinding '$BINDING' does not bind the ServiceAccount 'deploy-bot' of namespace 'ops-rbac'"
    exit 1
fi

echo "✅ RoleBinding '$BINDING' binds ClusterRole 'deployment-reader' to ServiceAccount 'deploy-bot'"
exit 0
