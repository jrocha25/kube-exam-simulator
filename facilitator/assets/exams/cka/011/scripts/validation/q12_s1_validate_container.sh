#!/bin/bash
set -e

NAMESPACE="ds-deice"
DS="deice"
CONTAINER="deice"
IMAGE="nginx:1.27.4"

if ! kubectl get daemonset "$DS" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ DaemonSet '$DS' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get daemonset "$DS" -n "$NAMESPACE" -o json)

COUNT=$(jq '.spec.template.spec.containers | length' <<<"$JSON")
if [[ "$COUNT" != "1" ]]; then
    echo "❌ DaemonSet '$DS' has ${COUNT} containers, expected exactly 1"
    exit 1
fi

NAME=$(jq -r '.spec.template.spec.containers[0].name' <<<"$JSON")
GOT_IMAGE=$(jq -r '.spec.template.spec.containers[0].image' <<<"$JSON")
if [[ "$NAME" != "$CONTAINER" ]]; then
    echo "❌ The container is named '${NAME}', expected '${CONTAINER}'"
    exit 1
fi
if [[ "$GOT_IMAGE" != "$IMAGE" ]]; then
    echo "❌ The container runs image '${GOT_IMAGE}', expected '${IMAGE}'"
    exit 1
fi

echo "✅ DaemonSet '$DS' has one container named '$CONTAINER' running '$IMAGE'"
exit 0
