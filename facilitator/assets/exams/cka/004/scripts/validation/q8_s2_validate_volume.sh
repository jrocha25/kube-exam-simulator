#!/bin/bash
set -e

NAMESPACE="logistics"
DEPLOYMENT="shipment-tracker"
VOLUME="app-logs"
MOUNT_PATH="/var/log/app"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

POD_SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '.spec.template.spec')

EMPTY_DIR=$(echo "$POD_SPEC" | jq --arg v "$VOLUME" '[.volumes // [] | .[] | select(.name == $v and .emptyDir != null)] | length')
if [[ "$EMPTY_DIR" == "0" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has no emptyDir volume named '$VOLUME'"
    exit 1
fi

for CONTAINER in tracker log-shipper; do
    MOUNTS=$(echo "$POD_SPEC" | jq --arg c "$CONTAINER" --arg v "$VOLUME" --arg p "$MOUNT_PATH" '
        [((.containers // []) + (.initContainers // []))[]
          | select(.name == $c)
          | (.volumeMounts // [])[]
          | select(.name == $v and .mountPath == $p)] | length')
    if [[ "$MOUNTS" == "0" ]]; then
        echo "❌ Container '$CONTAINER' does not mount the volume '$VOLUME' at '$MOUNT_PATH'"
        exit 1
    fi
done

echo "✅ Both containers share the emptyDir volume '$VOLUME' at '$MOUNT_PATH'"
exit 0
