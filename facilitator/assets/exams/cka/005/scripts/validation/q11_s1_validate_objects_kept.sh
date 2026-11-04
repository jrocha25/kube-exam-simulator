#!/bin/bash
set -e

NAMESPACE="rbac-broken"

for object in "serviceaccount/sync-agent" "role/sync-agent-role" "rolebinding/sync-agent-binding"; do
    if ! kubectl get "$object" -n "$NAMESPACE" &> /dev/null; then
        echo "❌ '$object' no longer exists in namespace '$NAMESPACE'"
        exit 1
    fi
done

ROLEREF=$(kubectl get rolebinding sync-agent-binding -n "$NAMESPACE" -o jsonpath='{.roleRef.name}')
if [[ "$ROLEREF" != "sync-agent-role" ]]; then
    echo "❌ 'sync-agent-binding' references '$ROLEREF', expected 'sync-agent-role'"
    exit 1
fi

SUBJECT_NS=$(kubectl get rolebinding sync-agent-binding -n "$NAMESPACE" -o json \
    | jq -r '[.subjects[]? | select(.kind=="ServiceAccount" and .name=="sync-agent") | (.namespace // "rbac-broken")][0] // empty')
if [[ "$SUBJECT_NS" != "$NAMESPACE" ]]; then
    echo "❌ 'sync-agent-binding' binds the ServiceAccount 'sync-agent' of '${SUBJECT_NS:-<no subject>}', not of '$NAMESPACE'"
    exit 1
fi

echo "✅ The ServiceAccount, Role and RoleBinding kept their names and the binding targets the right subject"
exit 0
