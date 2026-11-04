#!/bin/bash
set -e

NAMESPACE="qos-hangar"
DEPLOYMENT="hangar-ops"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json)

COUNT=$(jq '.spec.template.spec.containers | length' <<<"$JSON")
NAME=$(jq -r '.spec.template.spec.containers[0].name // ""' <<<"$JSON")
if [[ "$COUNT" != "1" || "$NAME" != "ops" ]]; then
    echo "❌ '$DEPLOYMENT' has ${COUNT} container(s), first named '${NAME}'; expected exactly one named 'ops'"
    exit 1
fi

DESIRED=$(jq -r '.spec.replicas // 0' <<<"$JSON")
if [[ "$DESIRED" != "2" ]]; then
    echo "❌ '$DEPLOYMENT' declares ${DESIRED} replicas, expected 2"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    [[ "${READY:-0}" == "2" ]] && break
    sleep 5
done
if [[ "${READY:-0}" != "2" ]]; then
    echo "❌ '$DEPLOYMENT' has ${READY:-0} ready replicas, expected 2"
    exit 1
fi

echo "✅ '$DEPLOYMENT' still has 2 ready replicas and one container named 'ops'"
exit 0
