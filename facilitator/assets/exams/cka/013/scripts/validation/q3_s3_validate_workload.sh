#!/bin/bash
set -e

NAMESPACE="helm-tide"
DEPLOYMENT="tidewatch"
IMAGE="nginx:1.27.4"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

GOT_IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$GOT_IMAGE" != "$IMAGE" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' runs '$GOT_IMAGE', expected '$IMAGE'"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    [[ "$READY" == "2" ]] && break
    sleep 5
done
if [[ "$READY" != "2" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has ${READY:-0} ready replicas, expected 2"
    exit 1
fi

echo "✅ '$DEPLOYMENT' has 2 ready replicas on $IMAGE"
exit 0
