#!/bin/bash
set -e

# The half of the init-container/sidecar distinction that question 10 takes from
# the other side. seed-ledger has to be a real init container: exactly one entry
# under initContainers, which ran to completion and is NOT still up. An init
# container carrying restartPolicy: Always is a native sidecar -- it never
# terminates, and the other containers would be waiting on it.

NAMESPACE="wl-waveform"
POD="waveform-writer"
INIT="seed-ledger"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

COUNT=$(jq '(.spec.initContainers // []) | length' <<<"$JSON")
NAMES=$(jq -r '[(.spec.initContainers // [])[].name] | join(",")' <<<"$JSON")
if [[ "$COUNT" != "1" || "$NAMES" != "$INIT" ]]; then
    echo "❌ '$POD' must have exactly one init container named '${INIT}' (found ${COUNT}: '${NAMES:-none}')"
    exit 1
fi

POLICY=$(jq -r '.spec.initContainers[0].restartPolicy // ""' <<<"$JSON")
if [[ "$POLICY" == "Always" ]]; then
    echo "❌ '${INIT}' carries restartPolicy: Always, which makes it a native sidecar rather than an init container"
    echo "   It is supposed to run to completion and get out of the way."
    exit 1
fi

for _ in $(seq 1 6); do
    REASON=$(jq -r '(.status.initContainerStatuses // [])[0].state.terminated.reason // ""' <<<"$JSON")
    [[ "$REASON" == "Completed" ]] && break
    sleep 5
    JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
done

REASON=$(jq -r '(.status.initContainerStatuses // [])[0].state.terminated.reason // ""' <<<"$JSON")
CODE=$(jq -r '(.status.initContainerStatuses // [])[0].state.terminated.exitCode // ""' <<<"$JSON")
if [[ "$REASON" != "Completed" || "$CODE" != "0" ]]; then
    echo "❌ '${INIT}' has not terminated successfully (reason '${REASON:-still running}', exit code '${CODE:-none}')"
    exit 1
fi

echo "✅ '${INIT}' is the Pod's only init container and ran to completion"
exit 0
