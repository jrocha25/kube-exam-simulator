#!/bin/bash
set -e

# The other step a mock exam marked wrong: the shared volume has to be mounted in
# all THREE containers, the init container included, at the same path. The init
# container is where the file is created, so a Pod that mounts it only in the two
# regular containers writes the header into the init container's own filesystem
# and throws it away.

NAMESPACE="wl-waveform"
POD="waveform-writer"
VOLUME="ledger"
MOUNT="/srv/waveforms"
CONTAINERS="seed-ledger waveform-app ledger-tail"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

for c in $CONTAINERS; do
    if ! jq -e --arg c "$c" --arg v "$VOLUME" --arg m "$MOUNT" '
        [ ((.spec.containers // []) + (.spec.initContainers // []))[]
          | select(.name == $c)
          | (.volumeMounts // [])[]
          | select(.name == $v and .mountPath == $m) ] | length > 0' <<<"$JSON" >/dev/null; then
        echo "❌ Container '${c}' does not mount volume '${VOLUME}' at '${MOUNT}'"
        exit 1
    fi
done

for _ in $(seq 1 6); do
    PHASE=$(jq -r '.status.phase // ""' <<<"$JSON")
    NOT_READY=$(jq -r '[(.status.containerStatuses // [])[] | select(.ready != true) | .name] | join(",")' <<<"$JSON")
    [[ "$PHASE" == "Running" && -z "$NOT_READY" ]] && break
    sleep 5
    JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
done

PHASE=$(jq -r '.status.phase // ""' <<<"$JSON")
NOT_READY=$(jq -r '[(.status.containerStatuses // [])[] | select(.ready != true) | .name] | join(",")' <<<"$JSON")
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ '$POD' is ${PHASE:-absent}, expected Running"
    exit 1
fi
if [[ -n "$NOT_READY" ]]; then
    echo "❌ These containers of '$POD' are not ready: ${NOT_READY}"
    exit 1
fi

echo "✅ All three containers mount '${VOLUME}' at '${MOUNT}', and '$POD' is Running with both regular containers ready"
exit 0
