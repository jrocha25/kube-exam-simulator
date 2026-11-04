#!/bin/bash
set -e

PV_NAME="archive-pv"
NAMESPACE="archive"
PVC_NAME="archive-pvc"

if ! kubectl get pv "$PV_NAME" &> /dev/null; then
    echo "❌ PersistentVolume '$PV_NAME' not found"
    exit 1
fi

RECLAIM=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')
if [[ "$RECLAIM" != "Retain" ]]; then
    echo "❌ PersistentVolume '$PV_NAME' must keep the reclaim policy 'Retain' (got: '$RECLAIM')"
    exit 1
fi

SC=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.storageClassName}')
if [[ "$SC" != "archive-manual" ]]; then
    echo "❌ PersistentVolume '$PV_NAME' must keep the storage class 'archive-manual' (got: '$SC')"
    exit 1
fi

CAPACITY=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.capacity.storage}')
if [[ "$CAPACITY" != "1Gi" ]]; then
    echo "❌ PersistentVolume '$PV_NAME' must keep the capacity '1Gi' (got: '$CAPACITY')"
    exit 1
fi

PHASE=""
for _ in $(seq 1 12); do
    PHASE=$(kubectl get pv "$PV_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$PHASE" == "Bound" ]]; then
        break
    fi
    sleep 5
done

if [[ "$PHASE" != "Bound" ]]; then
    echo "❌ PersistentVolume '$PV_NAME' is not Bound (current phase: '${PHASE:-<none>}')"
    exit 1
fi

CLAIM_NAME=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.claimRef.name}')
CLAIM_NS=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.claimRef.namespace}')
if [[ "$CLAIM_NAME" != "$PVC_NAME" ]] || [[ "$CLAIM_NS" != "$NAMESPACE" ]]; then
    echo "❌ PersistentVolume '$PV_NAME' is not claimed by '$NAMESPACE/$PVC_NAME' (got: '$CLAIM_NS/$CLAIM_NAME')"
    exit 1
fi

echo "✅ PersistentVolume '$PV_NAME' was reused and is bound to '$NAMESPACE/$PVC_NAME'"
exit 0
