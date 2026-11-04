#!/bin/bash
set -e

NAMESPACE="sts-ledger"
STS="ledger-db"
EXPECTED_REPLICAS=2

JSON=$(kubectl get statefulset "$STS" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ StatefulSet '$STS' not found in namespace '$NAMESPACE'"
    exit 1
fi

SERVICE=$(jq -r '.spec.serviceName // empty' <<<"$JSON")
REPLICAS=$(jq -r '.spec.replicas' <<<"$JSON")
CNAME=$(jq -r '.spec.template.spec.containers[0].name' <<<"$JSON")
IMAGE=$(jq -r '.spec.template.spec.containers[0].image' <<<"$JSON")
[[ "$SERVICE" == "$STS" ]]                 || { echo "❌ serviceName is '${SERVICE:-unset}', expected $STS"; exit 1; }
[[ "$REPLICAS" == "$EXPECTED_REPLICAS" ]]  || { echo "❌ replicas is $REPLICAS, expected $EXPECTED_REPLICAS"; exit 1; }
[[ "$CNAME" == "db" ]]                     || { echo "❌ container is named '$CNAME', expected db"; exit 1; }
[[ "$IMAGE" == "redis:7.4-alpine" ]]       || { echo "❌ container image is '$IMAGE', expected redis:7.4-alpine"; exit 1; }
POLICY=$(jq -r '.spec.podManagementPolicy // "OrderedReady"' <<<"$JSON")
[[ "$POLICY" == "Parallel" ]]              || { echo "❌ podManagementPolicy is '$POLICY', expected Parallel (replicas start one after the other)"; exit 1; }

for _ in $(seq 1 12); do
    READY=$(kubectl get statefulset "$STS" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    [[ "${READY:-0}" == "$EXPECTED_REPLICAS" ]] && break
    sleep 5
done
if [[ "${READY:-0}" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$STS' has ${READY:-0}/$EXPECTED_REPLICAS ready replicas"
    exit 1
fi

echo "✅ StatefulSet '$STS' has $EXPECTED_REPLICAS ready replicas behind Service '$SERVICE'"
exit 0
