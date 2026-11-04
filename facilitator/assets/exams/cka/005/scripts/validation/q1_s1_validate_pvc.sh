#!/bin/bash
set -e

NAMESPACE="store-data"
PVC="ledger-data"

if ! kubectl get pvc "$PVC" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ PersistentVolumeClaim '$PVC' not found in namespace '$NAMESPACE'"
    exit 1
fi

PHASE=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [[ "$PHASE" != "Bound" ]]; then
    echo "❌ PersistentVolumeClaim '$PVC' is '$PHASE', expected 'Bound'"
    exit 1
fi

MODES=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.spec.accessModes[*]}')
if [[ "$MODES" != "ReadWriteOnce" ]]; then
    echo "❌ Incorrect access modes on '$PVC'. Expected 'ReadWriteOnce', got '$MODES'"
    exit 1
fi

REQUEST=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}')
if [[ "$REQUEST" != "1Gi" ]]; then
    echo "❌ Incorrect storage request on '$PVC'. Expected '1Gi', got '$REQUEST'"
    exit 1
fi

VOLUME=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
if [[ -z "$VOLUME" ]]; then
    echo "❌ '$PVC' is not backed by a PersistentVolume"
    exit 1
fi

echo "✅ '$PVC' is bound to '$VOLUME' with 1Gi ReadWriteOnce"
exit 0
