#!/bin/bash
set -e

NAMESPACE="kube-system"
DEPLOYMENT="metrics-server"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    [[ "${READY:-0}" -ge 1 ]] && break
    sleep 5
done
if [[ "${READY:-0}" -lt 1 ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has no ready replica"
    exit 1
fi

echo "✅ The metrics server is running in ${NAMESPACE}"
exit 0
