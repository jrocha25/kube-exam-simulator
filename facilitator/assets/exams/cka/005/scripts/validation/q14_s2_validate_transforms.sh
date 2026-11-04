#!/bin/bash
set -e

NAMESPACE="kustom-app"
DEPLOYMENT="prod-web"

SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$SPEC" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

IMAGE=$(echo "$SPEC" | jq -r '.spec.template.spec.containers[0].image')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ '$DEPLOYMENT' runs '$IMAGE', expected 'nginx:1.27.4'"
    exit 1
fi

LABEL=$(echo "$SPEC" | jq -r '.metadata.labels.tier // empty')
if [[ "$LABEL" != "frontend" ]]; then
    echo "❌ '$DEPLOYMENT' carries tier='${LABEL:-<none>}', expected 'frontend'"
    exit 1
fi

SVC_LABEL=$(kubectl get service prod-web -n "$NAMESPACE" -o jsonpath='{.metadata.labels.tier}' 2>/dev/null || true)
if [[ "$SVC_LABEL" != "frontend" ]]; then
    echo "❌ Service 'prod-web' carries tier='${SVC_LABEL:-<none>}', expected 'frontend' on every resource"
    exit 1
fi

echo "✅ The overlay applied the image, name prefix and common label transformations"
exit 0
