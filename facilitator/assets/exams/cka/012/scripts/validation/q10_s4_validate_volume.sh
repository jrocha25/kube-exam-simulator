#!/bin/bash
set -e

# All three containers, init containers included, searched together: a native
# sidecar lives under initContainers and still has to mount the volume.

NAMESPACE="wl-shipper"
POD="trace-shipper"
VOLUME="spool"
MOUNT="/var/spool/traces"
CONTAINERS="trace-app prepare-spool log-forwarder"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

if ! jq -e --arg v "$VOLUME" '[(.spec.volumes // [])[] | select(.name == $v) | select(.emptyDir != null)] | length == 1' <<<"$JSON" >/dev/null; then
    NAMES=$(jq -r '[(.spec.volumes // [])[].name] | join(",")' <<<"$JSON")
    echo "❌ '$POD' has no emptyDir volume named '${VOLUME}' (volumes: '${NAMES:-none}')"
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

echo "✅ All three containers mount the '${VOLUME}' emptyDir at '${MOUNT}'"
exit 0
