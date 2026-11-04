#!/bin/bash
set -e

NAMESPACE="edge-helm"
RELEASE="web-edge"
IMAGE="nginx:1.27.4"

if ! kubectl get deployment "$RELEASE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$RELEASE' not found in namespace '$NAMESPACE'"
    exit 1
fi

CURRENT=$(kubectl get deployment "$RELEASE" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$CURRENT" != "$IMAGE" ]]; then
    echo "❌ The rollback did not restore the image. Expected '$IMAGE', got '$CURRENT'"
    exit 1
fi

echo "✅ The rollback restored the image '$IMAGE'"
exit 0
