#!/bin/bash
set -e

NAMESPACE="sts-ledger"
STS="ledger-db"

JSON=$(kubectl get statefulset "$STS" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ StatefulSet '$STS' not found in namespace '$NAMESPACE'"
    exit 1
fi

TEMPLATE=$(jq -r '.spec.volumeClaimTemplates[]? | select(.metadata.name=="data") | "\(.spec.storageClassName // "") \(.spec.resources.requests.storage // "")"' <<<"$JSON")
if [[ "$TEMPLATE" != "standard 100Mi" ]]; then
    echo "❌ Expected a volumeClaimTemplate 'data' requesting 100Mi from StorageClass standard (found: ${TEMPLATE:-none})"
    exit 1
fi

MOUNT=$(jq -r '.spec.template.spec.containers[0].volumeMounts[]? | select(.name=="data") | .mountPath' <<<"$JSON")
if [[ "$MOUNT" != "/data" ]]; then
    echo "❌ The 'data' volume is mounted at '${MOUNT:-nowhere}', expected /data"
    exit 1
fi

for i in 0 1; do
    PVC="data-${STS}-${i}"
    PHASE=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$PHASE" != "Bound" ]]; then
        echo "❌ PersistentVolumeClaim '$PVC' is ${PHASE:-missing}, expected Bound"
        exit 1
    fi
done

echo "✅ data-${STS}-0 and data-${STS}-1 are Bound and mounted at /data"
exit 0
