#!/bin/bash
set -e

NAMESPACE="rbac-report"
BINDING="report-reader-binding"
ROLE="config-reader"
SA="report-reader"

if ! kubectl get rolebinding "$BINDING" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ RoleBinding '$BINDING' not found in namespace '$NAMESPACE'"
    exit 1
fi

KIND=$(kubectl get rolebinding "$BINDING" -n "$NAMESPACE" -o jsonpath='{.roleRef.kind}')
NAME=$(kubectl get rolebinding "$BINDING" -n "$NAMESPACE" -o jsonpath='{.roleRef.name}')
if [[ "$KIND" != "Role" || "$NAME" != "$ROLE" ]]; then
    echo "❌ RoleBinding '$BINDING' references '$KIND/$NAME', expected 'Role/$ROLE'"
    exit 1
fi

MATCH=$(kubectl get rolebinding "$BINDING" -n "$NAMESPACE" -o json | jq --arg sa "$SA" --arg ns "$NAMESPACE" \
    '[.subjects[]? | select(.kind == "ServiceAccount" and .name == $sa and .namespace == $ns)] | length')
if [[ "$MATCH" == "0" ]]; then
    echo "❌ RoleBinding '$BINDING' does not name ServiceAccount '$SA' in namespace '$NAMESPACE'"
    exit 1
fi

echo "✅ RoleBinding '$BINDING' grants Role '$ROLE' to ServiceAccount '$SA'"
exit 0
