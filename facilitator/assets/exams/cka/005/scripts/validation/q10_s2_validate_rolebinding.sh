#!/bin/bash
set -e

NAMESPACE="rbac-ops"
BINDING="oncall-debug"

if ! kubectl get rolebinding "$BINDING" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ RoleBinding '$BINDING' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get rolebinding "$BINDING" -n "$NAMESPACE" -o json)

KIND=$(echo "$SPEC" | jq -r '.roleRef.kind')
NAME=$(echo "$SPEC" | jq -r '.roleRef.name')
if [[ "$KIND" != "ClusterRole" || "$NAME" != "pod-debugger" ]]; then
    echo "❌ '$BINDING' references '$KIND/$NAME', expected 'ClusterRole/pod-debugger'"
    exit 1
fi

SUBJECT=$(echo "$SPEC" | jq -r '[.subjects[]? | select(.kind=="ServiceAccount" and .name=="oncall" and ((.namespace // "rbac-ops") == "rbac-ops"))] | length')
if [[ "$SUBJECT" == "0" ]]; then
    echo "❌ '$BINDING' does not bind the ServiceAccount 'rbac-ops/oncall'"
    exit 1
fi

if ! kubectl get serviceaccount oncall -n "$NAMESPACE" &> /dev/null; then
    echo "❌ ServiceAccount 'oncall' not found in namespace '$NAMESPACE'"
    exit 1
fi

echo "✅ '$BINDING' grants ClusterRole/pod-debugger to 'oncall' inside '$NAMESPACE' only"
exit 0
