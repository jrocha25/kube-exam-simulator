#!/bin/bash
set -e

NAMESPACE="helm-broken"
DEPLOYMENT="orderbook"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

READY=""
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [[ "${READY:-0}" == "3" ]]; then
        break
    fi
    sleep 5
done

if [[ "${READY:-0}" != "3" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has ${READY:-0} ready replicas, expected 3"
    exit 1
fi

IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' runs '$IMAGE', expected 'nginx:1.27.4'"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' runs 3 ready replicas of nginx:1.27.4"
exit 0
