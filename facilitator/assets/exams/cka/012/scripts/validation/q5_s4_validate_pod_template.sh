#!/bin/bash
set -e

# The Pod template, and the one assertion that has to be phrased as an absence:
# activeDeadlineSeconds is a valid field on a PodSpec as well as on a JobSpec, so
# putting it here is accepted in silence and even appears to work. The CronJob is
# checked to exist first, because "the field is not set" is trivially true of an
# object that does not exist.

NAMESPACE="wl-digest"
CRONJOB="trace-compactor"
CONTAINER="compactor"
IMAGE="busybox:1.36"

if ! kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ CronJob '$CRONJOB' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" -o json)
POD='.spec.jobTemplate.spec.template.spec'

RESTART=$(jq -r "${POD}.restartPolicy // \"\"" <<<"$JSON")
if [[ "$RESTART" != "OnFailure" ]]; then
    echo "❌ The Pod template's restartPolicy is '${RESTART:-unset}', expected 'OnFailure'"
    exit 1
fi

STRAY=$(jq -r "${POD}.activeDeadlineSeconds // \"\"" <<<"$JSON")
if [[ -n "$STRAY" ]]; then
    echo "❌ activeDeadlineSeconds is set to '${STRAY}' on the Pod template"
    echo "   It is a valid field there, which is why nothing complained, but it bounds the Pod"
    echo "   rather than the Job. The Job's own deadline belongs at .spec.jobTemplate.spec."
    exit 1
fi

COUNT=$(jq "${POD}.containers | length" <<<"$JSON")
NAME=$(jq -r "${POD}.containers[0].name // \"\"" <<<"$JSON")
IMG=$(jq -r "${POD}.containers[0].image // \"\"" <<<"$JSON")
if [[ "$COUNT" != "1" || "$NAME" != "$CONTAINER" || "$IMG" != "$IMAGE" ]]; then
    echo "❌ The Pod template must have exactly one container named '${CONTAINER}' running '${IMAGE}'"
    echo "   Found ${COUNT} container(s), '${NAME:-none}' running '${IMG:-none}'"
    exit 1
fi

echo "✅ The Pod template restarts only on failure, runs '${CONTAINER}', and carries no Job-level field"
exit 0
