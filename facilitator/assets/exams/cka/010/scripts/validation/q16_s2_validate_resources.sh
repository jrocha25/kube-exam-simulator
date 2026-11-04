#!/bin/bash
set -e

NAMESPACE="ts-memory"
DEPLOYMENT="render-worker"

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

C='.spec.template.spec.containers[0]'
LIMIT=$(jq -r "$C.resources.limits.memory // \"unset\"" <<<"$JSON")
REQ_MEM=$(jq -r "$C.resources.requests.memory // \"unset\"" <<<"$JSON")
REQ_CPU=$(jq -r "$C.resources.requests.cpu // \"unset\"" <<<"$JSON")
IMAGE=$(jq -r "$C.image" <<<"$JSON")
COMMAND=$(jq -r "$C.command | join(\" \")" <<<"$JSON")

if [[ "$LIMIT" != "128Mi" ]]; then
    echo "❌ The memory limit is '$LIMIT', expected 128Mi"
    exit 1
fi
if [[ "$REQ_MEM" != "16Mi" || "$REQ_CPU" != "50m" ]]; then
    echo "❌ The requests were changed (memory $REQ_MEM, cpu $REQ_CPU; expected 16Mi / 50m)"
    exit 1
fi
if [[ "$IMAGE" != "busybox:1.36" ]]; then
    echo "❌ The image was changed to '$IMAGE'"
    exit 1
fi
if ! grep -q "head -c 40000000" <<<"$COMMAND"; then
    echo "❌ The container command was changed"
    exit 1
fi

echo "✅ The container has a 128Mi limit and its requests, image and command are unchanged"
exit 0
