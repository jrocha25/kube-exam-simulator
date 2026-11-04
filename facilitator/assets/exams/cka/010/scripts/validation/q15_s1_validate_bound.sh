#!/bin/bash
set -e

NAMESPACE="ts-storage"
PVC="archive-claim"
PV="archive-pv"

if ! kubectl get pvc "$PVC" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ PersistentVolumeClaim '$PVC' not found in namespace '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 6); do
    PHASE=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Bound" ]] && break
    sleep 5
done
if [[ "$PHASE" != "Bound" ]]; then
    echo "❌ '$PVC' is ${PHASE:-missing}, expected Bound"
    exit 1
fi

VOLUME=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
if [[ "$VOLUME" != "$PV" ]]; then
    echo "❌ '$PVC' is bound to '$VOLUME', expected '$PV'"
    exit 1
fi

echo "✅ '$PVC' is Bound to '$PV'"
exit 0
