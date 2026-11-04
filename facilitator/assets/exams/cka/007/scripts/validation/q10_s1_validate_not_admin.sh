#!/bin/bash
set -e

USER="system:serviceaccount:rbac-excess:backup-agent"

check_denied() {
    local verb="$1" resource="$2" namespace="$3"
    local args=(auth can-i "$verb" "$resource" --as="$USER")
    [[ -n "$namespace" ]] && args+=(-n "$namespace")

    local answer
    answer=$(kubectl "${args[@]}" 2>/dev/null || true)
    if [[ "$answer" == "yes" ]]; then
        echo "❌ '$USER' can '$verb' '$resource'${namespace:+ in $namespace}; the account still holds administrative access"
        exit 1
    fi
}

check_denied delete nodes ""
check_denied patch  nodes ""
check_denied get    secrets kube-system
check_denied list   secrets rbac-excess
check_denied create deployments.apps rbac-excess
check_denied delete namespaces ""
check_denied create clusterrolebindings.rbac.authorization.k8s.io ""
check_denied '*'    '*' ""

echo "✅ 'backup-agent' no longer holds administrative access to the cluster"
exit 0
