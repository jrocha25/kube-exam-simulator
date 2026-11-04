#!/bin/bash
set -e

NAMESPACE="storage-manual"
PVC_NAME="logs-pvc"

if ! kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ PersistentVolumeClaim '$PVC_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

SC=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.storageClassName}')
if [[ "$SC" != "manual" ]]; then
    echo "❌ Incorrect storage class name. Expected 'manual', got '$SC'"
    exit 1
fi

ACCESS_MODE=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.accessModes[0]}')
if [[ "$ACCESS_MODE" != "ReadWriteOnce" ]]; then
    echo "❌ Incorrect access mode. Expected 'ReadWriteOnce', got '$ACCESS_MODE'"
    exit 1
fi

REQUEST=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}')
if [[ "$REQUEST" != "2Gi" ]]; then
    echo "❌ Incorrect storage request. Expected '2Gi', got '$REQUEST'"
    exit 1
fi

PHASE=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [[ "$PHASE" != "Bound" ]]; then
    echo "❌ PVC '$PVC_NAME' is not Bound (current phase: '$PHASE')"
    exit 1
fi

VOLUME=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
if [[ "$VOLUME" != "logs-pv" ]]; then
    echo "❌ PVC '$PVC_NAME' is bound to '$VOLUME' instead of 'logs-pv'"
    exit 1
fi

echo "✅ PersistentVolumeClaim '$PVC_NAME' is bound to 'logs-pv'"
exit 0
