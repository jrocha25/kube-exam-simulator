#!/bin/bash
set -e

NAMESPACE="ts-image"
DEPLOYMENT="billing-api"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="api")].image}')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ Container 'api' uses image '$IMAGE' instead of 'nginx:1.27.4'"
    exit 1
fi

echo "✅ Container 'api' uses the image nginx:1.27.4"
exit 0
