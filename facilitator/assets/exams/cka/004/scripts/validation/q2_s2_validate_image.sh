#!/bin/bash
set -e

NAMESPACE="media"
DEPLOYMENT="media-api"
CONTAINER="api"
IMAGE="nginx:1.27.4"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

CURRENT=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json \
    | jq -r --arg c "$CONTAINER" '.spec.template.spec.containers[] | select(.name == $c) | .image')
if [[ "$CURRENT" != "$IMAGE" ]]; then
    echo "❌ Container '$CONTAINER' must run '$IMAGE' (got: '${CURRENT:-<none>}')"
    exit 1
fi

echo "✅ Container '$CONTAINER' of '$DEPLOYMENT' runs '$IMAGE'"
exit 0
