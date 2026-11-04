#!/bin/bash
set -e

NAMESPACE="batch-jobs"
CRONJOB_NAME="db-backup"

if ! kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ CronJob '$CRONJOB_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

SUCCESS_LIMIT=$(kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.successfulJobsHistoryLimit}')
if [[ "$SUCCESS_LIMIT" != "2" ]]; then
    echo "❌ Incorrect successfulJobsHistoryLimit. Expected '2', got '$SUCCESS_LIMIT'"
    exit 1
fi

FAILED_LIMIT=$(kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.failedJobsHistoryLimit}')
if [[ "$FAILED_LIMIT" != "1" ]]; then
    echo "❌ Incorrect failedJobsHistoryLimit. Expected '1', got '$FAILED_LIMIT'"
    exit 1
fi

SUSPEND=$(kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.suspend}')
if [[ "$SUSPEND" == "true" ]]; then
    echo "❌ CronJob '$CRONJOB_NAME' must not be suspended"
    exit 1
fi

echo "✅ CronJob '$CRONJOB_NAME' has the required history limits"
exit 0
