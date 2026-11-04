#!/bin/bash
set -e

NAMESPACE="store-data"
DEPLOYMENT="ledger-api"
PVC="ledger-data"
MOUNT_PATH="/var/lib/ledger"

VOLUME_NAME=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath="{.spec.template.spec.volumes[?(@.persistentVolumeClaim.claimName=='$PVC')].name}" 2>/dev/null || true)
if [[ -z "$VOLUME_NAME" ]]; then
    echo "❌ '$DEPLOYMENT' has no volume backed by the claim '$PVC'"
    exit 1
fi

FOUND=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name=='api')].volumeMounts[?(@.name=='$VOLUME_NAME')].mountPath}")
if [[ "$FOUND" != "$MOUNT_PATH" ]]; then
    echo "❌ Container 'api' does not mount '$PVC' at '$MOUNT_PATH' (got '${FOUND:-<none>}')"
    exit 1
fi

POD=$(kubectl get pods -n "$NAMESPACE" -l app=ledger-api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
    echo "❌ No Running Pod of '$DEPLOYMENT' found"
    exit 1
fi

echo "✅ Pod '$POD' mounts '$PVC' at '$MOUNT_PATH'"
exit 0
