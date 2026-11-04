#!/bin/bash
set -e

NAMESPACE="rbac-jobs"
USER="system:serviceaccount:rbac-jobs:scheduler-bot"

check_allowed() {
    local verb="$1" resource="$2"
    local answer
    answer=$(kubectl auth can-i "$verb" "$resource" --as="$USER" -n "$NAMESPACE" 2>/dev/null || true)
    if [[ "$answer" != "yes" ]]; then
        echo "❌ '$USER' cannot '$verb' '$resource' in '$NAMESPACE'"
        exit 1
    fi
}

check_allowed get  ingresses.networking.k8s.io
check_allowed list ingresses.networking.k8s.io
check_allowed get  pods
check_allowed list pods

echo "✅ 'scheduler-bot' can read Ingresses and Pods in '$NAMESPACE'"
exit 0
