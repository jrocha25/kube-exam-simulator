#!/bin/bash
set -e

NAMESPACE="archive"
PVC_NAME="archive-pvc"

if ! kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ PersistentVolumeClaim '$PVC_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

ACCESS_MODE=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.accessModes[0]}')
if [[ "$ACCESS_MODE" != "ReadWriteOnce" ]]; then
    echo "❌ Incorrect access mode. Expected 'ReadWriteOnce', got '$ACCESS_MODE'"
    exit 1
fi

REQUEST=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}')
if [[ "$REQUEST" != "500Mi" ]]; then
    echo "❌ Incorrect storage request. Expected '500Mi', got '$REQUEST'"
    exit 1
fi

PHASE=""
for _ in $(seq 1 12); do
    PHASE=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$PHASE" == "Bound" ]]; then
        break
    fi
    sleep 5
done

if [[ "$PHASE" != "Bound" ]]; then
    echo "❌ PersistentVolumeClaim '$PVC_NAME' is not Bound (current phase: '${PHASE:-<none>}')"
    exit 1
fi

VOLUME=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
if [[ "$VOLUME" != "archive-pv" ]]; then
    echo "❌ PersistentVolumeClaim '$PVC_NAME' is bound to '$VOLUME' instead of 'archive-pv'"
    exit 1
fi

echo "✅ PersistentVolumeClaim '$PVC_NAME' is bound to 'archive-pv'"
exit 0
