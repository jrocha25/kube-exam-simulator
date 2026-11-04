#!/bin/bash
set -e

NAMESPACE="batch-jobs"
CRONJOB_NAME="db-backup"

if ! kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ CronJob '$CRONJOB_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

SCHEDULE=$(kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.schedule}')
if [[ "$SCHEDULE" != "*/5 * * * *" ]]; then
    echo "❌ Incorrect schedule. Expected '*/5 * * * *', got '$SCHEDULE'"
    exit 1
fi

CONTAINER_NAME=$(kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].name}')
if [[ "$CONTAINER_NAME" != "backup" ]]; then
    echo "❌ Incorrect container name. Expected 'backup', got '$CONTAINER_NAME'"
    exit 1
fi

IMAGE=$(kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')
if [[ "$IMAGE" != "busybox:1.36" ]]; then
    echo "❌ Incorrect image. Expected 'busybox:1.36', got '$IMAGE'"
    exit 1
fi

CMD=$(kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" -o json | jq -r '[.spec.jobTemplate.spec.template.spec.containers[0].command // [], .spec.jobTemplate.spec.template.spec.containers[0].args // []] | flatten | join(" ")')
if [[ "$CMD" != *"echo backup completed"* ]]; then
    echo "❌ Container 'backup' does not run the required command (got: '$CMD')"
    exit 1
fi

RESTART_POLICY=$(kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.jobTemplate.spec.template.spec.restartPolicy}')
if [[ "$RESTART_POLICY" != "OnFailure" ]]; then
    echo "❌ Incorrect restart policy. Expected 'OnFailure', got '$RESTART_POLICY'"
    exit 1
fi

echo "✅ CronJob '$CRONJOB_NAME' is configured correctly"
exit 0
