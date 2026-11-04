#!/bin/bash
set -e

NAMESPACE="ts-sched"
DEPLOYMENT="analytics"
NODE="k3d-cluster-agent-0"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
if [[ "$READY" != "3" ]]; then
    echo "❌ Expected 3 ready replicas, got '$READY'"
    exit 1
fi

RUNNING_ON_NODE=$(kubectl get pods -n "$NAMESPACE" -l app=analytics -o json | jq --arg node "$NODE" '[.items[]
  | select(.status.phase == "Running" and .spec.nodeName == $node)] | length')
if [[ "$RUNNING_ON_NODE" != "3" ]]; then
    echo "❌ Expected 3 Running Pods on node '$NODE', found $RUNNING_ON_NODE"
    exit 1
fi

echo "✅ All 3 analytics Pods are Running on node '$NODE'"
exit 0
