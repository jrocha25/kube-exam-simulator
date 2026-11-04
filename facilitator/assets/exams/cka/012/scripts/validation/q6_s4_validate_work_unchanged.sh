#!/bin/bash
set -e

# A constraint check: the fix was supposed to be the two scheduling fields, not a
# shorter sleep or a different image. Guarded on the concurrency fix being in
# place so that it cannot pay out on an untouched cluster.

NAMESPACE="wl-rotate"
CRONJOB="digest-trim"
IMAGE="busybox:1.36"
SCHEDULE="*/1 * * * *"
NEEDLE="sleep 150"

if ! kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ CronJob '$CRONJOB' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" -o json)

if [[ "$(jq -r '.spec.concurrencyPolicy // ""' <<<"$JSON")" != "Forbid" ]]; then
    echo "❌ '$CRONJOB' still allows overlapping runs, so there is nothing to confirm yet"
    exit 1
fi

GOT_SCHEDULE=$(jq -r '.spec.schedule // ""' <<<"$JSON")
if [[ "$GOT_SCHEDULE" != "$SCHEDULE" ]]; then
    echo "❌ The schedule is now '${GOT_SCHEDULE:-unset}', and it was to stay '${SCHEDULE}'"
    exit 1
fi

POD='.spec.jobTemplate.spec.template.spec'
COUNT=$(jq "${POD}.containers | length" <<<"$JSON")
IMG=$(jq -r "${POD}.containers[0].image // \"\"" <<<"$JSON")
CMD=$(jq -r "${POD}.containers[0] | ((.command // []) + (.args // [])) | join(\" \")" <<<"$JSON")

if [[ "$COUNT" != "1" || "$IMG" != "$IMAGE" ]]; then
    echo "❌ The Pod template must still have one container running '${IMAGE}' (found ${COUNT}, '${IMG:-none}')"
    exit 1
fi
if [[ "$CMD" != *"$NEEDLE"* ]]; then
    echo "❌ The container's command no longer does its original work"
    echo "   Expected it to still contain '${NEEDLE}', found: ${CMD:-none}"
    echo "   Shortening the work is not the same as bounding the run."
    exit 1
fi

echo "✅ '$CRONJOB' still runs the same work on the same schedule"
exit 0
