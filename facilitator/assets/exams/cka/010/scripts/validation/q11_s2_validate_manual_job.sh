#!/bin/bash
set -e

NAMESPACE="batch-reports"
JOB="report-sweeper-manual"
CRONJOB="report-sweeper"

JSON=$(kubectl get job "$JOB" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Job '$JOB' not found in namespace '$NAMESPACE'"
    exit 1
fi

# "kubectl create job --from=cronjob/..." stamps the Job it makes; a Job written
# by hand does not carry this, however closely it copies the template.
INSTANTIATE=$(jq -r '.metadata.annotations["cronjob.kubernetes.io/instantiate"] // empty' <<<"$JSON")
if [[ "$INSTANTIATE" != "manual" ]]; then
    echo "❌ '$JOB' was not created from the CronJob (no cronjob.kubernetes.io/instantiate=manual annotation)"
    exit 1
fi

IMAGE=$(jq -r '.spec.template.spec.containers[0].image' <<<"$JSON")
CNAME=$(jq -r '.spec.template.spec.containers[0].name' <<<"$JSON")
if [[ "$IMAGE" != "busybox:1.36" || "$CNAME" != "sweeper" ]]; then
    echo "❌ '$JOB' does not run the '$CRONJOB' template (container '$CNAME' / '$IMAGE')"
    exit 1
fi

for _ in $(seq 1 12); do
    SUCCEEDED=$(kubectl get job "$JOB" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo 0)
    [[ "${SUCCEEDED:-0}" -ge 1 ]] && break
    sleep 5
done
if [[ "${SUCCEEDED:-0}" -lt 1 ]]; then
    echo "❌ '$JOB' has not completed successfully"
    exit 1
fi

echo "✅ '$JOB' was created from '$CRONJOB' and completed"
exit 0
