#!/bin/bash
set -e

NAMESPACE="node-agents"
DS_NAME="log-agent"

if ! kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ DaemonSet '$DS_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
DESIRED=$(kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}')
READY=$(kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" -o jsonpath='{.status.numberReady}')

if [[ "$DESIRED" != "$NODE_COUNT" ]]; then
    echo "❌ DaemonSet '$DS_NAME' is scheduled on $DESIRED node(s) but the cluster has $NODE_COUNT node(s)"
    exit 1
fi

if [[ "$READY" != "$DESIRED" ]]; then
    echo "❌ Only $READY of $DESIRED DaemonSet Pods are ready"
    exit 1
fi

echo "✅ DaemonSet '$DS_NAME' runs a ready Pod on all $NODE_COUNT nodes"
exit 0
