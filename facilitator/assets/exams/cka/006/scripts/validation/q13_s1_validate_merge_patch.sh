#!/bin/bash
set -e

NAMESPACE="kustom-stage"
DEPLOYMENT="api"
OVERLAY="/tmp/exam/q13/overlays/staging"

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

LEVEL=$(echo "$JSON" | jq -r '[.spec.template.spec.containers[0].env[]? | select(.name=="LOG_LEVEL") | .value] | first // empty')
if [[ "$LEVEL" != "debug" ]]; then
    echo "❌ The container's LOG_LEVEL is '${LEVEL:-<unset>}', expected 'debug'"
    exit 1
fi

READY=$(echo "$JSON" | jq -r '.status.readyReplicas // 0')
if [[ "$READY" -lt 1 ]]; then
    echo "❌ '$DEPLOYMENT' has no ready replicas"
    exit 1
fi

# The patch had to be a separate file referenced from the overlay, not inlined
# edits to the base.
if ! grep -rqs "LOG_LEVEL" "$OVERLAY"; then
    echo "❌ No file under '$OVERLAY' mentions LOG_LEVEL -- the patch is not in the overlay"
    exit 1
fi

echo "✅ The strategic merge patch set LOG_LEVEL=debug on the running Deployment"
exit 0
