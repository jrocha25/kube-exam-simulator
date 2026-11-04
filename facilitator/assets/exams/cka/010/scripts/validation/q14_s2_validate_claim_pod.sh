#!/bin/bash
set -e

NAMESPACE="stor-bulk"
PVC="bulk-data"
POD="bulk-writer"
SC="bulk-retain"

CLAIM=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$CLAIM" ]]; then
    echo "❌ PersistentVolumeClaim '$PVC' not found in namespace '$NAMESPACE'"
    exit 1
fi
CLASS=$(jq -r '.spec.storageClassName // empty' <<<"$CLAIM")
SIZE=$(jq -r '.spec.resources.requests.storage // empty' <<<"$CLAIM")
MODES=$(jq -r '.spec.accessModes | join(",")' <<<"$CLAIM")
if [[ "$CLASS" != "$SC" || "$SIZE" != "500Mi" || "$MODES" != "ReadWriteOnce" ]]; then
    echo "❌ '$PVC' must request 500Mi ReadWriteOnce from '$SC' (found $SIZE $MODES from '${CLASS:-none}')"
    exit 1
fi

if ! kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi
MOUNTED=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json \
    | jq -r --arg c "$PVC" '.spec.volumes[] | select(.persistentVolumeClaim.claimName==$c) | .name' | head -1)
if [[ -z "$MOUNTED" ]]; then
    echo "❌ Pod '$POD' does not use claim '$PVC'"
    exit 1
fi

# WaitForFirstConsumer: the claim only binds once the Pod is scheduled, so the
# Pod and the claim converge together.
for _ in $(seq 1 12); do
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    BOUND=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Running" && "$BOUND" == "Bound" ]] && break
    sleep 5
done
if [[ "$BOUND" != "Bound" ]]; then
    echo "❌ '$PVC' is ${BOUND:-Pending}, expected Bound"
    exit 1
fi
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is ${PHASE:-missing}, expected Running"
    exit 1
fi

PV=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
RECLAIM=$(kubectl get pv "$PV" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null || true)
if [[ "$RECLAIM" != "Retain" ]]; then
    echo "❌ The volume '$PV' behind '$PVC' has reclaim policy '${RECLAIM:-unknown}', expected Retain"
    exit 1
fi

echo "✅ '$PVC' is Bound to '$PV' (Retain) and '$POD' is Running"
exit 0
