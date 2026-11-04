#!/bin/bash
set -e

NAMESPACE="kustom-prod"
DEPLOYMENT="prod-trade-app"

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    echo "   (the namePrefix or namespace transformation was not applied)"
    exit 1
fi

IMAGE=$(echo "$JSON" | jq -r '.spec.template.spec.containers[0].image')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ '$DEPLOYMENT' runs '$IMAGE', expected 'nginx:1.27.4'"
    exit 1
fi

LABEL=$(echo "$JSON" | jq -r '.metadata.labels.env // empty')
if [[ "$LABEL" != "production" ]]; then
    echo "❌ '$DEPLOYMENT' carries env='${LABEL:-<none>}', expected 'production'"
    exit 1
fi

CONTAINER=$(echo "$JSON" | jq -r '.spec.template.spec.containers[0].name')
if [[ "$CONTAINER" != "trade-app" ]]; then
    echo "❌ The container is named '$CONTAINER', expected 'trade-app'"
    exit 1
fi

echo "✅ The namespace, name prefix, label and image transformations were applied"
exit 0
