#!/bin/bash
set -e

NAMESPACE="node-agents"
DS_NAME="log-agent"

if ! kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ DaemonSet '$DS_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

CONTAINER_COUNT=$(kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" -o json | jq '.spec.template.spec.containers | length')
if [[ "$CONTAINER_COUNT" != "1" ]]; then
    echo "❌ DaemonSet '$DS_NAME' must define exactly one container (found $CONTAINER_COUNT)"
    exit 1
fi

CONTAINER_NAME=$(kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].name}')
if [[ "$CONTAINER_NAME" != "agent" ]]; then
    echo "❌ Incorrect container name. Expected 'agent', got '$CONTAINER_NAME'"
    exit 1
fi

IMAGE=$(kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$IMAGE" != "busybox:1.36" ]]; then
    echo "❌ Incorrect image. Expected 'busybox:1.36', got '$IMAGE'"
    exit 1
fi

CMD=$(kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" -o json | jq -r '[.spec.template.spec.containers[0].command // [], .spec.template.spec.containers[0].args // []] | flatten | join(" ")')
if [[ "$CMD" != *"while true; do sleep 30; done"* ]]; then
    echo "❌ Container 'agent' does not run the required command (got: '$CMD')"
    exit 1
fi

LABEL=$(kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.metadata.labels.app}')
if [[ "$LABEL" != "log-agent" ]]; then
    echo "❌ Pod template is missing the label app=log-agent (got: '$LABEL')"
    exit 1
fi

echo "✅ DaemonSet '$DS_NAME' is configured correctly"
exit 0
