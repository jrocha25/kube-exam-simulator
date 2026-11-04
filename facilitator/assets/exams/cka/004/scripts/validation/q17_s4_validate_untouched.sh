#!/bin/bash
set -e

NAMESPACE="edge-broken"
DEPLOYMENT="shop"
SERVICE="shop-svc"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "3" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep 3 replicas (got: '$REPLICAS')"
    exit 1
fi

IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep the image 'nginx:1.27.4' (got: '$IMAGE')"
    exit 1
fi

LABEL=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.metadata.labels.app}')
if [[ "$LABEL" != "shop" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' Pods must keep the label 'app=shop' (got: 'app=$LABEL')"
    exit 1
fi

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SVC_TYPE=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.type}')
SVC_PORT=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')
SVC_TARGET=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].targetPort}')
SVC_SELECTOR=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.selector.app}')

if [[ "$SVC_TYPE" != "ClusterIP" ]] || [[ "$SVC_PORT" != "80" ]] || [[ "$SVC_TARGET" != "80" ]] || [[ "$SVC_SELECTOR" != "shop" ]]; then
    echo "❌ Service '$SERVICE' was modified. Expected a ClusterIP Service on port 80 -> 80 selecting 'app=shop'"
    exit 1
fi

echo "✅ The Gateway API objects were repaired without touching the Deployment or the Service"
exit 0
