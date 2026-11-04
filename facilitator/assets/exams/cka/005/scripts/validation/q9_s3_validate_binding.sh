#!/bin/bash
set -e

NAMESPACE="rbac-app"
BINDING="report-runner-read"

if ! kubectl get rolebinding "$BINDING" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ RoleBinding '$BINDING' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get rolebinding "$BINDING" -n "$NAMESPACE" -o json)

KIND=$(echo "$SPEC" | jq -r '.roleRef.kind')
NAME=$(echo "$SPEC" | jq -r '.roleRef.name')
if [[ "$KIND" != "Role" || "$NAME" != "report-reader" ]]; then
    echo "❌ '$BINDING' references '$KIND/$NAME', expected 'Role/report-reader'"
    exit 1
fi

SUBJECT=$(echo "$SPEC" | jq -r '[.subjects[]? | select(.kind=="ServiceAccount" and .name=="report-runner" and ((.namespace // "rbac-app") == "rbac-app"))] | length')
if [[ "$SUBJECT" == "0" ]]; then
    echo "❌ '$BINDING' does not bind the ServiceAccount 'rbac-app/report-runner'"
    exit 1
fi

echo "✅ '$BINDING' binds Role/report-reader to the ServiceAccount 'report-runner'"
exit 0
