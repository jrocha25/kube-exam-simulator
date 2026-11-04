#!/bin/bash
set -e

NAMESPACE="storage-dynamic"
POD_NAME="archiver"

if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Pod '$POD_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

PHASE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD_NAME' is not Running (current phase: '$PHASE')"
    exit 1
fi

IMAGE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[?(@.name=="archiver")].image}')
if [[ "$IMAGE" != "busybox:1.36" ]]; then
    echo "❌ Container 'archiver' uses image '$IMAGE' instead of 'busybox:1.36'"
    exit 1
fi

MOUNT_PATH=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[?(@.name=="archiver")].volumeMounts[?(@.name=="archive")].mountPath}')
if [[ "$MOUNT_PATH" != "/archive" ]]; then
    echo "❌ Volume 'archive' is not mounted at '/archive' (got: '$MOUNT_PATH')"
    exit 1
fi

CLAIM=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[?(@.name=="archive")].persistentVolumeClaim.claimName}')
if [[ "$CLAIM" != "archive-pvc" ]]; then
    echo "❌ Volume 'archive' is not backed by PVC 'archive-pvc' (got: '$CLAIM')"
    exit 1
fi

echo "✅ Pod '$POD_NAME' is Running and mounts 'archive-pvc' at /archive"
exit 0
