#!/bin/bash
set -e

NAMESPACE="edge-helm"
RELEASE="web-edge"

if ! helm status "$RELEASE" -n "$NAMESPACE" > /dev/null 2>&1; then
    echo "❌ Helm release '$RELEASE' not found in namespace '$NAMESPACE'"
    exit 1
fi

REPLICA_VALUE=$(helm get values "$RELEASE" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.replicaCount // empty')
if [[ "$REPLICA_VALUE" != "3" ]]; then
    echo "❌ The effective release values must set replicaCount to 3 (got: '${REPLICA_VALUE:-<none>}')"
    exit 1
fi

READY=""
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$RELEASE" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [[ "$READY" == "3" ]]; then
        break
    fi
    sleep 5
done

if [[ "$READY" != "3" ]]; then
    echo "❌ Deployment '$RELEASE' does not have 3 ready replicas (ready: '${READY:-0}')"
    exit 1
fi

echo "✅ Release '$RELEASE' is back to 3 replicas"
exit 0
