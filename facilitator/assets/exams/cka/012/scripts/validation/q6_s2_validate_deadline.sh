#!/bin/bash
set -e

# The second fault, and the same level trap as question 5: a deadline on the Pod
# template is accepted silently, so the check reads the Job template's spec
# exactly and says where the value was found if it is in the wrong place.

NAMESPACE="wl-rotate"
CRONJOB="digest-trim"
WANT="45"

if ! kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ CronJob '$CRONJOB' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" -o json)

GOT=$(jq -r '.spec.jobTemplate.spec.activeDeadlineSeconds // ""' <<<"$JSON")
if [[ "$GOT" != "$WANT" ]]; then
    echo "❌ .spec.jobTemplate.spec.activeDeadlineSeconds is '${GOT:-unset}', expected ${WANT}"
    POD_LEVEL=$(jq -r '.spec.jobTemplate.spec.template.spec.activeDeadlineSeconds // ""' <<<"$JSON")
    if [[ -n "$POD_LEVEL" ]]; then
        echo "   It is set to '${POD_LEVEL}' on the Pod template. That is a valid field there, which is"
        echo "   why nothing complained, but it bounds the Pod rather than the Job."
    fi
    exit 1
fi

echo "✅ A run of '$CRONJOB' is abandoned after ${WANT} seconds, set on the Job template spec"
exit 0
