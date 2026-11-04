#!/bin/bash
set -e

# Current state, with no wait. A candidate who fixed the CronJob shortly before
# the exam ended may still have one 150-second run finishing, which is allowed;
# waiting for the pile to drain could burn the whole 90-second cap.
#
# Guarded twice, on the concurrency fix being in place and on the CronJob having
# actually run: early in an exam the seeded CronJob has only started one run, so
# "at most one active" is true of the broken state too -- it paid out on an
# unsolved evaluation until this guard was added.

NAMESPACE="wl-rotate"
CRONJOB="digest-trim"

if ! kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ CronJob '$CRONJOB' not found in namespace '$NAMESPACE'"
    exit 1
fi

POLICY=$(kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" -o jsonpath='{.spec.concurrencyPolicy}' 2>/dev/null || true)
if [[ "$POLICY" != "Forbid" ]]; then
    echo "❌ '$CRONJOB' still allows overlapping runs, so there is nothing to confirm yet"
    exit 1
fi

LAST=$(kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" -o jsonpath='{.status.lastScheduleTime}' 2>/dev/null || true)
if [[ -z "$LAST" ]]; then
    echo "❌ '$CRONJOB' has never scheduled a run, so there is nothing to judge"
    echo "   The schedule was supposed to stay as it was."
    exit 1
fi

ACTIVE=$(kubectl get jobs -n "$NAMESPACE" -o json 2>/dev/null \
    | jq '[.items[] | select((.status.active // 0) > 0)] | length' || true)

if [[ "${ACTIVE:-0}" -gt 1 ]]; then
    echo "❌ ${ACTIVE} runs of '$CRONJOB' are active at once"
    echo "   The runs that piled up before the fix do not go away on their own."
    exit 1
fi

echo "✅ At most one run of '$CRONJOB' is active (${ACTIVE:-0})"
exit 0
