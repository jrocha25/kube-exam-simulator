#!/bin/bash
set -e

NAMESPACE="ts-image"
DEPLOYMENT="billing-api"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "3" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep 3 replicas (got: '$REPLICAS')"
    exit 1
fi

CONTAINER_COUNT=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '.spec.template.spec.containers | length')
if [[ "$CONTAINER_COUNT" != "1" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep exactly one container (found $CONTAINER_COUNT)"
    exit 1
fi

CONTAINER_NAME=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].name}')
if [[ "$CONTAINER_NAME" != "api" ]]; then
    echo "❌ The container must keep the name 'api' (got: '$CONTAINER_NAME')"
    exit 1
fi

IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ The image was not fixed. Expected 'nginx:1.27.4', got '$IMAGE'"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' was fixed while keeping 3 replicas and the container name 'api'"
exit 0
