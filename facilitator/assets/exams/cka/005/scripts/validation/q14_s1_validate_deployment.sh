#!/bin/bash
set -e

NAMESPACE="kustom-app"
DEPLOYMENT="prod-web"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

DESIRED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$DESIRED" != "4" ]]; then
    echo "❌ '$DEPLOYMENT' declares '$DESIRED' replicas, expected '4'"
    exit 1
fi

READY=""
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [[ "${READY:-0}" == "4" ]]; then
        break
    fi
    sleep 5
done

if [[ "${READY:-0}" != "4" ]]; then
    echo "❌ '$DEPLOYMENT' has ${READY:-0} ready replicas, expected 4"
    exit 1
fi

if ! kubectl get service prod-web -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Service 'prod-web' not found in namespace '$NAMESPACE'; the whole base must be applied"
    exit 1
fi

echo "✅ '$DEPLOYMENT' runs 4 ready replicas in '$NAMESPACE'"
exit 0
