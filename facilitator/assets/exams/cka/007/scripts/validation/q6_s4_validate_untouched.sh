#!/bin/bash
set -e

NAMESPACE="rbac-review"

check_binding() {
    local name=$1 expected_kind=$2 expected_role=$3 expected_subject_kind=$4 expected_subject_name=$5

    if ! kubectl get rolebinding "$name" -n "$NAMESPACE" &> /dev/null; then
        echo "❌ RoleBinding '$name' no longer exists in '$NAMESPACE' and had to be left alone"
        exit 1
    fi

    local kind role
    kind=$(kubectl get rolebinding "$name" -n "$NAMESPACE" -o jsonpath='{.roleRef.kind}')
    role=$(kubectl get rolebinding "$name" -n "$NAMESPACE" -o jsonpath='{.roleRef.name}')
    if [[ "$kind" != "$expected_kind" || "$role" != "$expected_role" ]]; then
        echo "❌ RoleBinding '$name' now references $kind/$role, expected $expected_kind/$expected_role"
        exit 1
    fi

    local match
    match=$(kubectl get rolebinding "$name" -n "$NAMESPACE" -o json \
        | jq -r --arg k "$expected_subject_kind" --arg n "$expected_subject_name" \
            '[.subjects[]? | select(.kind == $k and .name == $n)] | length')
    if [[ "$match" != "1" ]]; then
        echo "❌ RoleBinding '$name' no longer names $expected_subject_kind/$expected_subject_name as a subject"
        exit 1
    fi
}

check_binding ops-readonly Role ops-viewer ServiceAccount ops-bot
check_binding deploy-managers ClusterRole edit Group delivery-team

if ! kubectl get role ops-viewer -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Role 'ops-viewer' no longer exists in '$NAMESPACE' and had to be left alone"
    exit 1
fi

OPS_VERBS=$(kubectl get role ops-viewer -n "$NAMESPACE" -o json \
    | jq -r '[.rules[]? | select(.resources | index("pods")) | .verbs[]] | unique | join(",")')
if [[ "$OPS_VERBS" != "get,list" ]]; then
    echo "❌ Role 'ops-viewer' grants '$OPS_VERBS' on pods, expected 'get,list' unchanged"
    exit 1
fi

echo "✅ The ops-readonly and deploy-managers bindings and the ops-viewer Role are unchanged"
exit 0
