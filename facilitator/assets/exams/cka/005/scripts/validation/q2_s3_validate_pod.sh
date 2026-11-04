#!/bin/bash
set -e

NAMESPACE="store-tier"
POD="archive-writer"
PVC="archive-claim"
MOUNT_PATH="/data"

if ! kubectl get pod "$POD" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is '$PHASE', expected 'Running'"
    exit 1
fi

VOLUME_NAME=$(kubectl get pod "$POD" -n "$NAMESPACE" \
    -o jsonpath="{.spec.volumes[?(@.persistentVolumeClaim.claimName=='$PVC')].name}")
if [[ -z "$VOLUME_NAME" ]]; then
    echo "❌ Pod '$POD' has no volume backed by the claim '$PVC'"
    exit 1
fi

FOUND=$(kubectl get pod "$POD" -n "$NAMESPACE" \
    -o jsonpath="{.spec.containers[?(@.name=='writer')].volumeMounts[?(@.name=='$VOLUME_NAME')].mountPath}")
if [[ "$FOUND" != "$MOUNT_PATH" ]]; then
    echo "❌ Container 'writer' does not mount '$PVC' at '$MOUNT_PATH' (got '${FOUND:-<none>}')"
    exit 1
fi

echo "✅ Pod '$POD' is Running and mounts '$PVC' at '$MOUNT_PATH'"
exit 0
