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

check_allowed get    cronjobs.batch
check_allowed list   cronjobs.batch
check_allowed create cronjobs.batch

# Creating one for real proves the grant resolves to the group the API actually serves.
if ! kubectl create cronjob probe-job --image=busybox:1.36 --schedule="*/30 * * * *" \
        -n "$NAMESPACE" --as="$USER" --dry-run=server &> /dev/null; then
    echo "❌ '$USER' could not create a CronJob in '$NAMESPACE'"
    exit 1
fi

echo "✅ 'scheduler-bot' can read and create CronJobs in '$NAMESPACE'"
exit 0
