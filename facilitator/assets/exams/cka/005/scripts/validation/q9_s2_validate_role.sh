#!/bin/bash
set -e

NAMESPACE="rbac-app"
ROLE="report-reader"
USER="system:serviceaccount:rbac-app:report-runner"

if ! kubectl get role "$ROLE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Role '$ROLE' not found in namespace '$NAMESPACE'"
    exit 1
fi

# Subresources have to be probed with --subresource: "can-i get pods/log" is
# parsed as "get the Pod named log" and silently answers a different question.
check_allowed() {
    local verb="$1" resource="$2" subresource="$3"
    local answer
    if [[ -n "$subresource" ]]; then
        answer=$(kubectl auth can-i "$verb" "$resource" --subresource="$subresource" --as="$USER" -n "$NAMESPACE" 2>/dev/null || true)
    else
        answer=$(kubectl auth can-i "$verb" "$resource" --as="$USER" -n "$NAMESPACE" 2>/dev/null || true)
    fi
    if [[ "$answer" != "yes" ]]; then
        echo "❌ '$USER' cannot '$verb' '$resource${subresource:+/$subresource}' in '$NAMESPACE'"
        exit 1
    fi
}

check_allowed get pods
check_allowed list pods
check_allowed watch pods
check_allowed get pods log
check_allowed get configmaps
check_allowed list configmaps

echo "✅ Role '$ROLE' grants the required read access in '$NAMESPACE'"
exit 0
