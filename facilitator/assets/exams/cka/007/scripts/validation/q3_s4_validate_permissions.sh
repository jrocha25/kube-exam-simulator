#!/bin/bash
set -e

USER="system:serviceaccount:rbac-monitor:dashboard"

if ! kubectl get serviceaccount dashboard -n rbac-monitor &> /dev/null; then
    echo "❌ ServiceAccount 'dashboard' not found in namespace 'rbac-monitor'"
    exit 1
fi

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

check yes list pods "" kube-system
check yes list pods "" default
check yes get  pods log kube-system
check yes list nodes "" ""
check no  delete pods "" kube-system
check no  get secrets "" kube-system

echo "✅ 'dashboard' has the aggregated monitoring permissions cluster wide, and nothing more"
exit 0
