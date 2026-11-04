#!/bin/bash
set -e

NAMESPACE="ts-sched"
DEPLOYMENT="analytics"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

MATCHES=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '[.spec.template.spec.tolerations // [] | .[]
  | select(.key == "workload" and .operator == "Equal" and .value == "analytics" and .effect == "NoSchedule")] | length')

if [[ "$MATCHES" == "0" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has no toleration with key 'workload', operator 'Equal', value 'analytics' and effect 'NoSchedule'"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' tolerates the workload=analytics:NoSchedule taint"
exit 0
