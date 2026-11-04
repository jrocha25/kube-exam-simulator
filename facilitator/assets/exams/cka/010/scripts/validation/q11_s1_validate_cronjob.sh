#!/bin/bash
set -e

NAMESPACE="batch-reports"
CRONJOB="report-sweeper"

JSON=$(kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ CronJob '$CRONJOB' not found in namespace '$NAMESPACE'"
    exit 1
fi

check() {  # label, jq path, expected
    local got
    got=$(jq -r "$2 // \"unset\"" <<<"$JSON")
    if [[ "$got" != "$3" ]]; then
        echo "❌ $1 is '$got', expected '$3'"
        exit 1
    fi
}

check "schedule"                   '.spec.schedule'                                         '*/10 * * * *'
check "concurrencyPolicy"          '.spec.concurrencyPolicy'                                'Forbid'
check "successfulJobsHistoryLimit" '.spec.successfulJobsHistoryLimit'                       '2'
check "failedJobsHistoryLimit"     '.spec.failedJobsHistoryLimit'                           '1'
check "backoffLimit"               '.spec.jobTemplate.spec.backoffLimit'                    '1'
check "activeDeadlineSeconds"      '.spec.jobTemplate.spec.activeDeadlineSeconds'           '90'
check "restartPolicy"              '.spec.jobTemplate.spec.template.spec.restartPolicy'     'Never'
check "container name"             '.spec.jobTemplate.spec.template.spec.containers[0].name'  'sweeper'
check "container image"            '.spec.jobTemplate.spec.template.spec.containers[0].image' 'busybox:1.36'

COUNT=$(jq '.spec.jobTemplate.spec.template.spec.containers | length' <<<"$JSON")
if [[ "$COUNT" != "1" ]]; then
    echo "❌ The Job template has $COUNT containers, expected 1"
    exit 1
fi

echo "✅ CronJob '$CRONJOB' is configured as specified"
exit 0
