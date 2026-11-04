#!/bin/bash
set -e

# The spec can describe a sidecar that never actually runs, so this reads status:
# prepare-spool terminated, log-forwarder still running, and the application
# ready at the same time. On Kubernetes 1.33+ a native sidecar reports itself in
# initContainerStatuses with state.running while the regular containers run.

NAMESPACE="wl-shipper"
POD="trace-shipper"
APP="trace-app"
FIRST="prepare-spool"
SIDECAR="log-forwarder"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 6); do
    SIDE_RUNNING=$(jq -r --arg n "$SIDECAR" '[(.status.initContainerStatuses // [])[] | select(.name == $n)][0].state.running.startedAt // ""' <<<"$JSON")
    APP_READY=$(jq -r --arg n "$APP" '[(.status.containerStatuses // [])[] | select(.name == $n)][0].ready // false' <<<"$JSON")
    [[ -n "$SIDE_RUNNING" && "$APP_READY" == "true" ]] && break
    sleep 5
    JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
done

FIRST_REASON=$(jq -r --arg n "$FIRST" '[(.status.initContainerStatuses // [])[] | select(.name == $n)][0].state.terminated.reason // ""' <<<"$JSON")
if [[ "$FIRST_REASON" != "Completed" ]]; then
    echo "❌ '${FIRST}' has not completed (state: ${FIRST_REASON:-not terminated})"
    exit 1
fi

SIDE_RUNNING=$(jq -r --arg n "$SIDECAR" '[(.status.initContainerStatuses // [])[] | select(.name == $n)][0].state.running.startedAt // ""' <<<"$JSON")
if [[ -z "$SIDE_RUNNING" ]]; then
    echo "❌ '${SIDECAR}' is not running"
    echo "   A native sidecar stays up for the life of the Pod; following a file it can read is what keeps it up."
    exit 1
fi

APP_READY=$(jq -r --arg n "$APP" '[(.status.containerStatuses // [])[] | select(.name == $n)][0].ready // false' <<<"$JSON")
if [[ "$APP_READY" != "true" ]]; then
    echo "❌ '${APP}' is not ready"
    exit 1
fi

echo "✅ '${FIRST}' completed, '${SIDECAR}' is running alongside a ready '${APP}'"
exit 0
