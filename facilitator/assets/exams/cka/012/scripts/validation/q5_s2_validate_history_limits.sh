#!/bin/bash
set -e

# Both limits are asked for at a non-default value on purpose:
# successfulJobsHistoryLimit defaults to 3 and failedJobsHistoryLimit to 1, so a
# question asking for 1 failed run would read back the right answer from a
# candidate who never set it.

NAMESPACE="wl-digest"
CRONJOB="trace-compactor"

if ! kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ CronJob '$CRONJOB' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" -o json)

SUCCESS=$(jq -r '.spec.successfulJobsHistoryLimit // ""' <<<"$JSON")
FAILED=$(jq -r '.spec.failedJobsHistoryLimit // ""' <<<"$JSON")

if [[ "$SUCCESS" != "2" ]]; then
    echo "❌ '$CRONJOB' keeps '${SUCCESS:-unset}' successful runs, expected 2"
    exit 1
fi
if [[ "$FAILED" != "2" ]]; then
    echo "❌ '$CRONJOB' keeps '${FAILED:-unset}' failed runs, expected 2"
    exit 1
fi

echo "✅ '$CRONJOB' keeps 2 successful and 2 failed runs in its history"
exit 0
