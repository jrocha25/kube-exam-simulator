#!/bin/bash
set -e

NAMESPACE="archive"
DEPLOYMENT="archive-api"
PVC_NAME="archive-pvc"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

CLAIM=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json \
    | jq -r '[.spec.template.spec.volumes // [] | .[] | select(.persistentVolumeClaim != null) | .persistentVolumeClaim.claimName] | join(",")')
if [[ "$CLAIM" != "$PVC_NAME" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must mount the claim '$PVC_NAME' (got: '${CLAIM:-<none>}')"
    exit 1
fi

READY=""
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [[ -n "$READY" ]] && [[ "$READY" -ge 1 ]]; then
        break
    fi
    sleep 5
done

if [[ -z "$READY" ]] || [[ "$READY" -lt 1 ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has no ready replica (ready: '${READY:-0}')"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' runs with the claim '$PVC_NAME' mounted"
exit 0
