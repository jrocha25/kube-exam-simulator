#!/bin/bash
set -e

NAMESPACE="rbac-tower"
NAME="flightplan-writer"

for kind in serviceaccount role rolebinding; do
    if ! kubectl get "$kind" "$NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "❌ ${kind^} '$NAME' not found in namespace '$NAMESPACE'"
        exit 1
    fi
done

SUBJECT=$(kubectl get rolebinding "$NAME" -n "$NAMESPACE" -o json \
    | jq -r --arg n "$NAME" --arg ns "$NAMESPACE" \
      '.subjects[]? | select(.kind=="ServiceAccount" and .name==$n and (.namespace // $ns)==$ns) | .name' | head -1)
if [[ -z "$SUBJECT" ]]; then
    echo "❌ RoleBinding '$NAME' does not bind the '$NAME' ServiceAccount of '$NAMESPACE'"
    exit 1
fi

ROLE_REF=$(kubectl get rolebinding "$NAME" -n "$NAMESPACE" -o jsonpath='{.roleRef.name}' 2>/dev/null || true)
if [[ "$ROLE_REF" != "$NAME" ]]; then
    echo "❌ RoleBinding '$NAME' refers to role '${ROLE_REF:-none}', expected '$NAME'"
    exit 1
fi

echo "✅ The ServiceAccount, Role and RoleBinding are in place"
exit 0
