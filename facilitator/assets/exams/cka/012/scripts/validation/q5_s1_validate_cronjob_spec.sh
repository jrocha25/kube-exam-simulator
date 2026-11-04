#!/bin/bash
set -e

# The fields that belong on the CronJob's own spec. startingDeadlineSeconds is
# the one of these that has no equivalent anywhere else in the object, so it is
# the cheapest evidence that the candidate read where each setting lives.

NAMESPACE="wl-digest"
CRONJOB="trace-compactor"

if ! kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ CronJob '$CRONJOB' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" -o json)

SCHEDULE=$(jq -r '.spec.schedule // ""' <<<"$JSON")
case "$SCHEDULE" in
    "*/20 * * * *"|"0,20,40 * * * *") ;;
    *)
        echo "❌ '$CRONJOB' runs on schedule '${SCHEDULE:-unset}', which is not every 20 minutes"
        exit 1
        ;;
esac

POLICY=$(jq -r '.spec.concurrencyPolicy // ""' <<<"$JSON")
if [[ "$POLICY" != "Forbid" ]]; then
    echo "❌ '$CRONJOB' has concurrencyPolicy '${POLICY:-unset}', expected 'Forbid'"
    exit 1
fi

DEADLINE=$(jq -r '.spec.startingDeadlineSeconds // ""' <<<"$JSON")
if [[ "$DEADLINE" != "30" ]]; then
    echo "❌ '$CRONJOB' has spec.startingDeadlineSeconds '${DEADLINE:-unset}', expected 30"
    echo "   This one belongs on the CronJob's own spec, next to the schedule."
    exit 1
fi

if [[ "$(jq -r '.spec.suspend // false' <<<"$JSON")" == "true" ]]; then
    echo "❌ '$CRONJOB' is suspended"
    exit 1
fi

echo "✅ '$CRONJOB' runs every 20 minutes, forbids overlap, skips a run more than 30s late, and is not suspended"
exit 0
