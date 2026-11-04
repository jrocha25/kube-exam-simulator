#!/bin/bash
set -e

NAMESPACE="ledger"
PV="ledger-pv"
PVC="ledger-data"
STATE=/tmp/exam/.q5

PV_JSON=$(kubectl get pv "$PV" -o json 2>/dev/null || true)
if [[ -z "$PV_JSON" ]]; then
    echo "❌ PersistentVolume '$PV' no longer exists"
    exit 1
fi
if [[ -f "$STATE/pv.uid" && "$(echo "$PV_JSON" | jq -r '.metadata.uid')" != "$(cat "$STATE/pv.uid")" ]]; then
    echo "❌ PersistentVolume '$PV' was deleted and recreated; reuse the original"
    exit 1
fi
if [[ "$(echo "$PV_JSON" | jq -r '.spec.persistentVolumeReclaimPolicy')" != "Retain" ]]; then
    echo "❌ '$PV' no longer has the Retain reclaim policy"
    exit 1
fi

PHASE=""
for _ in $(seq 1 6); do
    PHASE=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Bound" ]] && break
    [[ -z "$PHASE" ]] && break
    sleep 5
done
if [[ "$PHASE" != "Bound" ]]; then
    echo "❌ PersistentVolumeClaim '$PVC' in '$NAMESPACE' is not Bound (phase '${PHASE:-missing}')"
    exit 1
fi

VOLUME=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
if [[ "$VOLUME" != "$PV" ]]; then
    echo "❌ '$PVC' is bound to '$VOLUME', not to '$PV'"
    exit 1
fi

echo "✅ '$PVC' is bound to the original, retained '$PV'"
exit 0
