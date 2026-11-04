#!/bin/bash
set -e

NAMESPACE="ds-deice"
DS="deice"

if ! kubectl get daemonset "$DS" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ DaemonSet '$DS' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get daemonset "$DS" -n "$NAMESPACE" -o json)

CPU=$(jq -r '.spec.template.spec.containers[0].resources.requests.cpu // ""' <<<"$JSON")
MEMORY=$(jq -r '.spec.template.spec.containers[0].resources.requests.memory // ""' <<<"$JSON")

if [[ "$CPU" != "10m" ]]; then
    echo "❌ The container requests '${CPU:-nothing}' of CPU, expected '10m'"
    exit 1
fi
if [[ "$MEMORY" != "16Mi" ]]; then
    echo "❌ The container requests '${MEMORY:-nothing}' of memory, expected '16Mi'"
    exit 1
fi

echo "✅ The container requests 10m CPU and 16Mi memory"
exit 0
