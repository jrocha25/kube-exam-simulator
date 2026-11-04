#!/bin/bash
set -e

NAMESPACE="ts-config"
DEPLOYMENT="payments-worker"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "2" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must keep 2 replicas (got: '$REPLICAS')"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
if [[ "$READY" != "2" ]]; then
    echo "❌ Expected 2 ready replicas, got '$READY'"
    exit 1
fi

POD=$(kubectl get pods -n "$NAMESPACE" -l app=payments-worker --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$POD" ]]; then
    echo "❌ No Running Pod found for Deployment '$DEPLOYMENT'"
    exit 1
fi

VALUE=$(kubectl exec "$POD" -n "$NAMESPACE" --request-timeout=60s -- printenv PAYMENT_MODE 2>/dev/null | tr -d '\r\n')
if [[ "$VALUE" != "live" ]]; then
    echo "❌ Environment variable PAYMENT_MODE is '$VALUE' inside the container, expected 'live'"
    exit 1
fi

echo "✅ Both replicas are ready and PAYMENT_MODE is set to 'live'"
exit 0
