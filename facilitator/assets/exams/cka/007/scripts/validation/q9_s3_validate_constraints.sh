#!/bin/bash
set -e

USER="system:serviceaccount:rbac-jobs:scheduler-bot"

for object in "serviceaccount/scheduler-bot" "role/job-manager" "rolebinding/scheduler-bot-jobs"; do
    if ! kubectl get "$object" -n rbac-jobs &> /dev/null; then
        echo "❌ '$object' does not exist in namespace 'rbac-jobs'"
        exit 1
    fi
done

check_denied() {
    local verb="$1" resource="$2" namespace="$3"
    local answer
    answer=$(kubectl auth can-i "$verb" "$resource" --as="$USER" -n "$namespace" 2>/dev/null || true)
    if [[ "$answer" == "yes" ]]; then
        echo "❌ '$USER' can '$verb' '$resource' in '$namespace'; the grant is too broad"
        exit 1
    fi
}

check_denied get    cronjobs.batch                  rbac-jobs-staging
check_denied list   ingresses.networking.k8s.io     rbac-jobs-staging
check_denied delete cronjobs.batch                  rbac-jobs
check_denied get    secrets                         rbac-jobs

echo "✅ The grant keeps its original object names and stops at the 'rbac-jobs' namespace"
exit 0
