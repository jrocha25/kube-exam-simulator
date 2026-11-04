#!/bin/bash
set -e

NAMESPACE="ts-probe"
DEPLOYMENT="frontend"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "2" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep 2 replicas (got: '$REPLICAS')"
    exit 1
fi

IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="web")].image}')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep the image nginx:1.27.4 (got: '$IMAGE')"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
if [[ "$READY" != "2" ]]; then
    echo "❌ Expected 2 ready replicas, got '$READY'"
    exit 1
fi

RESTARTS=$(kubectl get pods -n "$NAMESPACE" -l app=frontend -o json | jq '[.items[].status.containerStatuses // [] | .[].restartCount] | add // 0')
if [[ "$RESTARTS" != "0" ]]; then
    echo "❌ frontend Pods have restarted $RESTARTS time(s); the liveness probe is still killing healthy containers"
    exit 1
fi

echo "✅ Both replicas of '$DEPLOYMENT' are ready and have not restarted"
exit 0
