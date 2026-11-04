#!/bin/bash
set -e

NAMESPACE="scale-batch"
DEPLOYMENT="render-worker"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="worker")].image}')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ Container 'worker' runs '${IMAGE:-<not found>}', expected 'nginx:1.27.4'"
    exit 1
fi

CPU=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="worker")].resources.requests.cpu}')
if [[ -z "$CPU" ]]; then
    echo "❌ Container 'worker' declares no CPU request"
    exit 1
fi

echo "✅ Container 'worker' declares a CPU request of '$CPU'"
exit 0
