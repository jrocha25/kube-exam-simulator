#!/bin/bash
set -e

NAMESPACE="sts-ledger"
SERVICE="ledger-db"

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

CLUSTER_IP=$(jq -r '.spec.clusterIP' <<<"$JSON")
if [[ "$CLUSTER_IP" != "None" ]]; then
    echo "❌ Service '$SERVICE' has clusterIP '$CLUSTER_IP' -- it is not headless"
    exit 1
fi

PORT=$(jq -r '[.spec.ports[]? | select(.port==6379)] | length' <<<"$JSON")
if [[ "${PORT:-0}" -lt 1 ]]; then
    echo "❌ Service '$SERVICE' does not expose port 6379"
    exit 1
fi

SELECTOR=$(jq -r '.spec.selector.app // empty' <<<"$JSON")
if [[ "$SELECTOR" != "ledger-db" ]]; then
    echo "❌ Service '$SERVICE' selects app='${SELECTOR:-none}', expected ledger-db"
    exit 1
fi

READY=$(kubectl get endpointslice -n "$NAMESPACE" -l "kubernetes.io/service-name=$SERVICE" -o json 2>/dev/null \
    | jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length')
if [[ "${READY:-0}" -lt 2 ]]; then
    echo "❌ Service '$SERVICE' has ${READY:-0} ready endpoints, expected 2"
    exit 1
fi

echo "✅ Service '$SERVICE' is headless on 6379 and selects both replicas"
exit 0
