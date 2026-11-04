#!/bin/bash
set -e

NAMESPACE="customs"
DEPLOYMENT="customs-gate"

READY=""
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    [[ "$READY" == "3" ]] && break
    [[ -z "$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o name 2>/dev/null)" ]] && break
    sleep 5
done
if [[ "$READY" != "3" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' in '$NAMESPACE' has ${READY:-0} of 3 ready replicas"
    exit 1
fi

echo "✅ '$DEPLOYMENT' has 3 ready replicas"
exit 0
