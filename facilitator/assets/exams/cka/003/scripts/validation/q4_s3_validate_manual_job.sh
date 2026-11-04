#!/bin/bash
set -e

NAMESPACE="batch-jobs"
JOB_NAME="db-backup-manual"

if ! kubectl get job "$JOB_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Job '$JOB_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

IMAGE=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$IMAGE" != "busybox:1.36" ]]; then
    echo "❌ Job '$JOB_NAME' does not use the CronJob template image. Expected 'busybox:1.36', got '$IMAGE'"
    exit 1
fi

CMD=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o json | jq -r '[.spec.template.spec.containers[0].command // [], .spec.template.spec.containers[0].args // []] | flatten | join(" ")')
if [[ "$CMD" != *"echo backup completed"* ]]; then
    echo "❌ Job '$JOB_NAME' does not run the CronJob command (got: '$CMD')"
    exit 1
fi

SUCCEEDED=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}')
if [[ -z "$SUCCEEDED" ]] || [[ "$SUCCEEDED" -lt 1 ]]; then
    echo "❌ Job '$JOB_NAME' has not completed successfully (succeeded: '$SUCCEEDED')"
    exit 1
fi

echo "✅ Job '$JOB_NAME' was created from the CronJob and completed successfully"
exit 0
