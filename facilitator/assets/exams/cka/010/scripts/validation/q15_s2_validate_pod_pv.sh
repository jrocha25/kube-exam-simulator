#!/bin/bash
set -e

NAMESPACE="ts-storage"
POD="archive-reader"
PVC="archive-claim"
PV="archive-pv"
RECORDED="/tmp/exam/q15/pv-spec.sha"

if ! kubectl get pv "$PV" >/dev/null 2>&1; then
    echo "❌ PersistentVolume '$PV' no longer exists -- it was not to be replaced"
    exit 1
fi

# The volume was the storage team's; the fix belonged on the claim.
if [[ -s "$RECORDED" ]]; then
    NOW=$(kubectl get pv "$PV" -o json | jq -S 'del(.spec.claimRef) | .spec' | sha256sum | cut -d' ' -f1)
    if [[ "$NOW" != "$(cat "$RECORDED")" ]]; then
        echo "❌ '$PV' was modified -- the claim was to be repaired, not the volume"
        exit 1
    fi
fi

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi
if ! jq -e --arg c "$PVC" '.spec.volumes[] | select(.persistentVolumeClaim.claimName==$c)' <<<"$JSON" >/dev/null; then
    echo "❌ Pod '$POD' no longer mounts claim '$PVC'"
    exit 1
fi

for _ in $(seq 1 12); do
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
done
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is ${PHASE:-missing}, expected Running"
    exit 1
fi

echo "✅ '$POD' is Running on '$PVC' and '$PV' is untouched"
exit 0
