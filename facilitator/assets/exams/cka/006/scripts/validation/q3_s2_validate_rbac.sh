#!/bin/bash
set -e

NAMESPACE="dev-team"
ROLE="dev-reader"
BINDING="mira-reader"

ROLE_JSON=$(kubectl get role "$ROLE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$ROLE_JSON" ]]; then
    echo "❌ Role '$ROLE' not found in namespace '$NAMESPACE'"
    exit 1
fi

RESOURCES=$(echo "$ROLE_JSON" | jq -r '[.rules[].resources[]] | unique | join(",")')
if [[ "$RESOURCES" != "pods,pods/log" ]]; then
    echo "❌ Role '$ROLE' covers resources '$RESOURCES', expected exactly 'pods,pods/log'"
    exit 1
fi

VERBS=$(echo "$ROLE_JSON" | jq -r '[.rules[].verbs[]] | unique | sort | join(",")')
if [[ "$VERBS" != "get,list,watch" ]]; then
    echo "❌ Role '$ROLE' grants verbs '$VERBS', expected exactly 'get,list,watch'"
    exit 1
fi

BIND_JSON=$(kubectl get rolebinding "$BINDING" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$BIND_JSON" ]]; then
    echo "❌ RoleBinding '$BINDING' not found in namespace '$NAMESPACE'"
    exit 1
fi

REF=$(echo "$BIND_JSON" | jq -r '.roleRef.kind + "/" + .roleRef.name')
if [[ "$REF" != "Role/$ROLE" ]]; then
    echo "❌ '$BINDING' references '$REF', expected 'Role/$ROLE'"
    exit 1
fi

SUBJECT=$(echo "$BIND_JSON" | jq -r '[.subjects[] | select(.kind=="User" and .name=="mira")] | length')
if [[ "$SUBJECT" -lt 1 ]]; then
    echo "❌ '$BINDING' does not bind the User 'mira'"
    exit 1
fi

echo "✅ Role '$ROLE' and RoleBinding '$BINDING' are correct"
exit 0
