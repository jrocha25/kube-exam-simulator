#!/bin/bash
set -e

NAMESPACE="storage-manual"
POD_NAME="log-writer"

if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Pod '$POD_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

PHASE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD_NAME' is not Running (current phase: '$PHASE')"
    exit 1
fi

IMAGE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[?(@.name=="writer")].image}')
if [[ "$IMAGE" != "busybox:1.36" ]]; then
    echo "❌ Container 'writer' uses image '$IMAGE' instead of 'busybox:1.36'"
    exit 1
fi

CMD=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o json | jq -r '[.spec.containers[] | select(.name=="writer") | (.command // []), (.args // [])] | flatten | join(" ")')
if [[ "$CMD" != *"date >> /data/app.log"* ]]; then
    echo "❌ Container 'writer' does not run the required command (got: '$CMD')"
    exit 1
fi

MOUNT_PATH=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[?(@.name=="writer")].volumeMounts[?(@.name=="logs")].mountPath}')
if [[ "$MOUNT_PATH" != "/data" ]]; then
    echo "❌ Volume 'logs' is not mounted at '/data' (got: '$MOUNT_PATH')"
    exit 1
fi

CLAIM=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[?(@.name=="logs")].persistentVolumeClaim.claimName}')
if [[ "$CLAIM" != "logs-pvc" ]]; then
    echo "❌ Volume 'logs' is not backed by PVC 'logs-pvc' (got: '$CLAIM')"
    exit 1
fi

echo "✅ Pod '$POD_NAME' is Running and mounts 'logs-pvc' at /data"
exit 0
