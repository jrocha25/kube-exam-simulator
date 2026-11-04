#!/bin/bash
set -e

NAMESPACE="ts-memory"
DEPLOYMENT="render-worker"
STABLE_SECONDS=30

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

# Cheap guards first: a Deployment that is not even ready pays no stability window.
for _ in $(seq 1 6); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    [[ "${READY:-0}" -ge 1 ]] && break
    sleep 5
done
if [[ "${READY:-0}" -lt 1 ]]; then
    echo "❌ '$DEPLOYMENT' has no ready replica"
    exit 1
fi

POD=$(kubectl get pods -n "$NAMESPACE" -l "app=$DEPLOYMENT" --field-selector status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
    echo "❌ No Running '$DEPLOYMENT' Pod"
    exit 1
fi

RESTARTS_BEFORE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}')
sleep "$STABLE_SECONDS"
RESTARTS_AFTER=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "gone")
LAST_STATE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null || true)

if [[ "$RESTARTS_AFTER" != "$RESTARTS_BEFORE" ]]; then
    echo "❌ '$POD' restarted during a ${STABLE_SECONDS}s window (${RESTARTS_BEFORE} -> ${RESTARTS_AFTER}${LAST_STATE:+, last state $LAST_STATE})"
    exit 1
fi

echo "✅ '$DEPLOYMENT' is Running and stayed up for ${STABLE_SECONDS}s without a restart"
exit 0
