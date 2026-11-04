#!/bin/bash
set -e

NAMESPACE="media"
DEPLOYMENT="media-api"
EXPECTED="image update to nginx 1.27.4"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

CAUSE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json \
    | jq -r '.metadata.annotations["kubernetes.io/change-cause"] // empty')
if [[ "$CAUSE" != "$EXPECTED" ]]; then
    echo "❌ The change cause was not recorded. Expected '$EXPECTED', got '${CAUSE:-<none>}'"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' records the change cause '$EXPECTED'"
exit 0
