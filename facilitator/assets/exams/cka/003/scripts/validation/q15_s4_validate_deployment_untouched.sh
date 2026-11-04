#!/bin/bash
set -e

NAMESPACE="ts-service"
DEPLOYMENT="catalog"
SERVICE="catalog-svc"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "3" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep 3 replicas (got: '$REPLICAS')"
    exit 1
fi

LABEL=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.metadata.labels.app}')
if [[ "$LABEL" != "catalog" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' Pods must keep the label app=catalog (got: 'app=$LABEL')"
    exit 1
fi

IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep the image nginx:1.27.4 (got: '$IMAGE')"
    exit 1
fi

PORT=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}')
if [[ "$PORT" != "80" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep container port 80 (got: '$PORT')"
    exit 1
fi

SELECTOR=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.selector.app}')
if [[ "$SELECTOR" != "catalog" ]]; then
    echo "❌ The Service '$SERVICE' was not fixed; it still selects 'app=$SELECTOR'"
    exit 1
fi

echo "✅ The Service was fixed without modifying the Deployment '$DEPLOYMENT'"
exit 0
