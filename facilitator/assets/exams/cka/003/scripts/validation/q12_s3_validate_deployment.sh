#!/bin/bash
set -e

NAMESPACE="drain-lab"
DEPLOYMENT="legacy-app"
NODE="k3d-cluster-agent-1"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

NODE_SELECTOR=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq -r '.spec.template.spec.nodeSelector // {} | length')
if [[ "$NODE_SELECTOR" != "0" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' still defines a nodeSelector"
    exit 1
fi

REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "3" ]]; then
    echo "❌ Incorrect replica count. Expected '3', got '$REPLICAS'"
    exit 1
fi

IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ Incorrect image. Expected 'nginx:1.27.4', got '$IMAGE'"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
if [[ "$READY" != "3" ]]; then
    echo "❌ Expected 3 ready replicas, got '$READY'"
    exit 1
fi

ON_NODE=$(kubectl get pods -n "$NAMESPACE" -l app=legacy-app -o json | jq --arg node "$NODE" '[.items[] | select(.spec.nodeName == $node)] | length')
if [[ "$ON_NODE" != "0" ]]; then
    echo "❌ $ON_NODE Pod(s) of '$DEPLOYMENT' are still running on node '$NODE'"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' has 3 ready replicas and none on node '$NODE'"
exit 0
