#!/bin/bash
set -e

# The first of the two faults: concurrencyPolicy was Allow, on a schedule shorter
# than the work takes.

NAMESPACE="wl-rotate"
CRONJOB="digest-trim"

if ! kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ CronJob '$CRONJOB' not found in namespace '$NAMESPACE'"
    exit 1
fi

POLICY=$(kubectl get cronjob "$CRONJOB" -n "$NAMESPACE" -o jsonpath='{.spec.concurrencyPolicy}' 2>/dev/null || true)
if [[ "$POLICY" != "Forbid" ]]; then
    echo "❌ '$CRONJOB' has concurrencyPolicy '${POLICY:-unset}'"
    echo "   'Allow' is the default and lets a new run start while the last one is still going."
    echo "   'Replace' would stop the overlap by killing the run in progress, which is not what was asked."
    exit 1
fi

echo "✅ '$CRONJOB' never starts a run while the previous one is still going"
exit 0
