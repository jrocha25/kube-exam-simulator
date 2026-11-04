#!/bin/bash
set -e

NAMESPACE="helm-pub"

# The chart labels its Deployment with app.kubernetes.io/name rather than
# .../instance, and names it after the release.
DEPLOYMENT=$(kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=podinfo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$DEPLOYMENT" ]] && kubectl get deployment podinfo -n "$NAMESPACE" &> /dev/null; then
    DEPLOYMENT=podinfo
fi
if [[ -z "$DEPLOYMENT" ]]; then
    echo "❌ No Deployment belonging to the 'podinfo' release found in namespace '$NAMESPACE'"
    exit 1
fi

READY=""
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [[ "${READY:-0}" == "4" ]]; then
        break
    fi
    sleep 5
done

if [[ "${READY:-0}" != "4" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has ${READY:-0} ready replicas, expected 4"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' runs 4 ready replicas"
exit 0
