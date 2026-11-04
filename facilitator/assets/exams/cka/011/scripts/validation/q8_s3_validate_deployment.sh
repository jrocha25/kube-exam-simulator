#!/bin/bash
set -e

NAMESPACE="stor-cargo"
DEPLOYMENT="cargo-hold"
CONTAINER="hold"
CLAIM="cargo-claim"
MOUNT="/var/cargo"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json)

VOLUME=$(jq -r --arg c "$CLAIM" \
    '.spec.template.spec.volumes[]? | select(.persistentVolumeClaim.claimName == $c) | .name' <<<"$JSON" | head -1)
if [[ -z "$VOLUME" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' does not use the '$CLAIM' claim as a volume"
    exit 1
fi

MOUNTED=$(jq -r --arg n "$CONTAINER" --arg v "$VOLUME" \
    '.spec.template.spec.containers[] | select(.name == $n) | .volumeMounts[]? | select(.name == $v) | .mountPath' \
    <<<"$JSON" | head -1)
if [[ "$MOUNTED" != "$MOUNT" ]]; then
    echo "❌ Container '$CONTAINER' mounts that volume at '${MOUNTED:-nowhere}', expected '$MOUNT'"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    [[ "${READY:-0}" -ge 1 ]] && break
    sleep 5
done
if [[ "${READY:-0}" -lt 1 ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has ${READY:-0} ready replicas, expected 1"
    exit 1
fi

echo "✅ '$DEPLOYMENT' is ready and mounts '$CLAIM' at '$MOUNT'"
exit 0
