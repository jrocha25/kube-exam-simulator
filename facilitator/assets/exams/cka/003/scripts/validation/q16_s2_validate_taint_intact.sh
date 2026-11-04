#!/bin/bash
set -e

NAMESPACE="ts-sched"
DEPLOYMENT="analytics"
NODE="k3d-cluster-agent-0"

TAINTS=$(kubectl get node "$NODE" -o json | jq '[.spec.taints // [] | .[]
  | select(.key == "workload" and .value == "analytics" and .effect == "NoSchedule")] | length')
if [[ "$TAINTS" == "0" ]]; then
    echo "❌ The taint workload=analytics:NoSchedule was removed from node '$NODE'"
    exit 1
fi

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

NODE_SELECTOR=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.nodeSelector.kubernetes\.io/hostname}')
if [[ "$NODE_SELECTOR" != "$NODE" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep the nodeSelector kubernetes.io/hostname=$NODE (got: '$NODE_SELECTOR')"
    exit 1
fi

REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "3" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep 3 replicas (got: '$REPLICAS')"
    exit 1
fi

MATCHES=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '[.spec.template.spec.tolerations // [] | .[]
  | select(.key == "workload" and .operator == "Equal" and .value == "analytics" and .effect == "NoSchedule")] | length')
if [[ "$MATCHES" == "0" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' was not fixed with the required toleration"
    exit 1
fi

echo "✅ The Deployment was fixed with a toleration while the node taint and nodeSelector stayed unchanged"
exit 0
