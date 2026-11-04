#!/bin/bash
set -e

NAMESPACE="ts-config"
DEPLOYMENT="payments-worker"

if kubectl get configmap payments-config -n "$NAMESPACE" &> /dev/null; then
    echo "❌ A ConfigMap named 'payments-config' was created in namespace '$NAMESPACE'; the existing 'payments-cfg' had to be used instead"
    exit 1
fi

if ! kubectl get configmap payments-cfg -n "$NAMESPACE" &> /dev/null; then
    echo "❌ The ConfigMap 'payments-cfg' no longer exists in namespace '$NAMESPACE'"
    exit 1
fi

MODE=$(kubectl get configmap payments-cfg -n "$NAMESPACE" -o jsonpath='{.data.PAYMENT_MODE}')
if [[ "$MODE" != "live" ]]; then
    echo "❌ The ConfigMap 'payments-cfg' was modified. Expected PAYMENT_MODE 'live', got '$MODE'"
    exit 1
fi

RETRY=$(kubectl get configmap payments-cfg -n "$NAMESPACE" -o jsonpath='{.data.RETRY_COUNT}')
if [[ "$RETRY" != "3" ]]; then
    echo "❌ The ConfigMap 'payments-cfg' was modified. Expected RETRY_COUNT '3', got '$RETRY'"
    exit 1
fi

MATCHES=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '[.spec.template.spec.containers[]
  | (.envFrom // []) | .[]
  | select(.configMapRef.name == "payments-cfg")] | length')
if [[ "$MATCHES" == "0" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' does not consume the existing ConfigMap 'payments-cfg' yet"
    exit 1
fi

echo "✅ The Deployment reuses the intact ConfigMap 'payments-cfg' and no replacement ConfigMap was created"
exit 0
