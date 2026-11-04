#!/bin/bash
set -e

NAMESPACE="kustom-app"
DEPLOYMENT="prod-web"

CM=$(kubectl get configmap -n "$NAMESPACE" -o json \
    | jq -r '[.items[].metadata.name | select(startswith("prod-web-content-"))][0] // empty')
if [[ -z "$CM" ]]; then
    echo "❌ No generated ConfigMap named 'prod-web-content-<hash>' found in '$NAMESPACE'"
    exit 1
fi

CONTENT=$(kubectl get configmap "$CM" -n "$NAMESPACE" -o jsonpath='{.data.index\.html}')
if [[ "$CONTENT" != "production" ]]; then
    echo "❌ '$CM' holds index.html='${CONTENT:-<empty>}', expected 'production'"
    exit 1
fi

REFERENCED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath="{.spec.template.spec.volumes[?(@.configMap.name=='$CM')].name}" 2>/dev/null || true)
if [[ -z "$REFERENCED" ]]; then
    echo "❌ '$DEPLOYMENT' does not mount the generated ConfigMap '$CM'"
    exit 1
fi

echo "✅ '$DEPLOYMENT' mounts the regenerated ConfigMap '$CM'"
exit 0
