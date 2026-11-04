#!/bin/bash
set -e

# The three fields that belong to the Job, at .spec.jobTemplate.spec. This is the
# step a mock exam marked wrong: activeDeadlineSeconds was put on the CronJob
# spec, where it is not a field at all.
#
# The paths are read exactly, so a field one level up or one level down is a miss
# and the message says where it was found instead.

NAMESPACE="wl-digest"
CRONJOB="trace-compactor"

if ! kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ CronJob '$CRONJOB' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" -o json)

check() {
    local field="$1" want="$2" got
    got=$(jq -r --arg f "$field" '.spec.jobTemplate.spec[$f] // ""' <<<"$JSON")
    if [[ "$got" != "$want" ]]; then
        echo "❌ .spec.jobTemplate.spec.${field} is '${got:-unset}', expected ${want}"
        local elsewhere
        elsewhere=$(jq -r --arg f "$field" '.spec.jobTemplate.spec.template.spec[$f] // ""' <<<"$JSON")
        if [[ -n "$elsewhere" ]]; then
            echo "   It is set to '${elsewhere}' on the Pod template instead, where it means something else."
        fi
        exit 1
    fi
}

check activeDeadlineSeconds 60
check backoffLimit 2
check ttlSecondsAfterFinished 120

echo "✅ '$CRONJOB' carries activeDeadlineSeconds=60, backoffLimit=2 and ttlSecondsAfterFinished=120 on the Job template spec"
exit 0
