#!/bin/bash
set -e

NAMESPACE="ts-config"
DEPLOYMENT="payments-worker"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

MATCHES=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '[.spec.template.spec.containers[]
  | select(.name == "worker")
  | (.envFrom // []) | .[]
  | select(.configMapRef.name == "payments-cfg")] | length')

if [[ "$MATCHES" == "0" ]]; then
    echo "❌ Container 'worker' does not use envFrom with configMapRef 'payments-cfg'"
    exit 1
fi

STALE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '[.spec.template.spec.containers[]
  | (.envFrom // []) | .[]
  | select(.configMapRef.name == "payments-config")] | length')

if [[ "$STALE" != "0" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' still references the non-existent ConfigMap 'payments-config'"
    exit 1
fi

echo "✅ Container 'worker' loads its environment from the ConfigMap 'payments-cfg'"
exit 0
