#!/bin/bash
set -e

USER="system:serviceaccount:rbac-ops:oncall"

# Subresources have to be probed with --subresource: "can-i create pods/exec" is
# parsed as "create the Pod named exec" and answers a different question.
check() {
    local expected="$1" verb="$2" resource="$3" subresource="$4" namespace="$5"
    local args=(auth can-i "$verb" "$resource" --as="$USER")
    [[ -n "$subresource" ]] && args+=(--subresource="$subresource")
    [[ -n "$namespace" ]] && args+=(-n "$namespace")

    local answer
    answer=$(kubectl "${args[@]}" 2>/dev/null || true)
    if [[ "$answer" != "$expected" ]]; then
        echo "❌ '$verb $resource${subresource:+/$subresource}${namespace:+ in $namespace}' returned '${answer:-<none>}', expected '$expected'"
        exit 1
    fi
}

check yes create pods exec rbac-ops
check yes get pods log rbac-ops
check no create pods exec rbac-ops-secure
check no get pods log rbac-ops-secure
check no create pods "" rbac-ops
check yes list nodes "" ""
check yes list persistentvolumes "" ""

echo "✅ 'oncall' can debug Pods only in 'rbac-ops' and read nodes and volumes cluster wide"
exit 0
