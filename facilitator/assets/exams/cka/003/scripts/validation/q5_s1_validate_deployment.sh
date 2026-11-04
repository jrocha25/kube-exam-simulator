#!/bin/bash
set -e

NAMESPACE="spread-lab"
DEPLOYMENT="spread-web"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "4" ]]; then
    echo "❌ Incorrect replica count. Expected '4', got '$REPLICAS'"
    exit 1
fi

LABEL=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.metadata.labels.app}')
if [[ "$LABEL" != "spread-web" ]]; then
    echo "❌ Pod template is missing the label app=spread-web (got: '$LABEL')"
    exit 1
fi

SELECTOR=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.selector.matchLabels.app}')
if [[ "$SELECTOR" != "spread-web" ]]; then
    echo "❌ Selector does not match app=spread-web (got: '$SELECTOR')"
    exit 1
fi

CONTAINER_NAME=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].name}')
if [[ "$CONTAINER_NAME" != "web" ]]; then
    echo "❌ Incorrect container name. Expected 'web', got '$CONTAINER_NAME'"
    exit 1
fi

IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ Incorrect image. Expected 'nginx:1.27.4', got '$IMAGE'"
    exit 1
fi

PORT=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}')
if [[ "$PORT" != "80" ]]; then
    echo "❌ Incorrect container port. Expected '80', got '$PORT'"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' is configured correctly"
exit 0
