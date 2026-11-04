#!/bin/bash

set -e

# Constraint check. The policy is already present and already selects the right
# Pods before the candidate starts, so this is worth a single mark -- it exists
# to catch a repair that deletes the policy or rebuilds the Deployment.

NAMESPACE="np-ts-selector"
CLIENT_NS="np-ts-selector-clients"
POLICY="inventory-ingress"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' has been deleted from '$NAMESPACE'"
    exit 1
fi

SELECTOR=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o jsonpath='{.spec.podSelector.matchLabels.app}')
if [[ "$SELECTOR" != "inventory" ]]; then
    echo "❌ '$POLICY' no longer selects the Pods labelled app=inventory"
    exit 1
fi

REPLICAS=$(kubectl get deployment checkout -n "$CLIENT_NS" -o jsonpath='{.spec.replicas}' 2> /dev/null || true)
if [[ "$REPLICAS" != "2" ]]; then
    echo "❌ Deployment 'checkout' declares '${REPLICAS:-<missing>}' replicas, expected 2"
    exit 1
fi

echo "✅ '$POLICY' and the 'checkout' Deployment are intact"
exit 0
