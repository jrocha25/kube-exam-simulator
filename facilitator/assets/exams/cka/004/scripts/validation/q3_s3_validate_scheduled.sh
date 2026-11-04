#!/bin/bash
set -e

NAMESPACE="analytics"
DEPLOYMENT="report-builder"
CONTAINER="builder"
IMAGE="nginx:1.27.4"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

CONTAINER_COUNT=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '.spec.template.spec.containers | length')
if [[ "$CONTAINER_COUNT" != "1" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep exactly one container (found $CONTAINER_COUNT)"
    exit 1
fi

CONTAINER_NAME=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].name}')
if [[ "$CONTAINER_NAME" != "$CONTAINER" ]]; then
    echo "❌ The container must keep the name '$CONTAINER' (got: '$CONTAINER_NAME')"
    exit 1
fi

CURRENT_IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$CURRENT_IMAGE" != "$IMAGE" ]]; then
    echo "❌ The container must keep the image '$IMAGE' (got: '$CURRENT_IMAGE')"
    exit 1
fi

UNSCHEDULED=$(kubectl get pods -n "$NAMESPACE" -l app=report-builder -o json \
    | jq '[.items[] | select((.spec.nodeName // "") == "")] | length')
if [[ "$UNSCHEDULED" != "0" ]]; then
    echo "❌ $UNSCHEDULED Pod(s) of '$DEPLOYMENT' are still waiting to be scheduled"
    exit 1
fi

echo "✅ Every Pod of '$DEPLOYMENT' is scheduled and the container is unchanged"
exit 0
