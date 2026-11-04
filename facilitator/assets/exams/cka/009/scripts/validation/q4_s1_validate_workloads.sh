#!/bin/bash

set -e

NAMESPACE="kustom-compose"

for ENTRY in "waybill-api:1" "waybill-cache:2"; do
    DEPLOYMENT="${ENTRY%%:*}"
    if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
        echo "❌ Deployment '$DEPLOYMENT' not found in '$NAMESPACE'; the overlay must compose both bases"
        exit 1
    fi
done

if ! kubectl get service waybill-api -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Service 'waybill-api' not found in '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 12); do
    API=$(kubectl get deployment waybill-api -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
    CACHE=$(kubectl get deployment waybill-cache -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
    [[ "$API" == "1" && "$CACHE" == "2" ]] && break
    sleep 5
done

if [[ "$API" != "1" || "$CACHE" != "2" ]]; then
    echo "❌ Ready replicas are waybill-api=${API:-0}/1 and waybill-cache=${CACHE:-0}/2"
    exit 1
fi

echo "✅ Both bases are composed into '$NAMESPACE' and running at the expected sizes"
exit 0
