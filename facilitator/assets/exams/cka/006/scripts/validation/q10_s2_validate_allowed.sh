#!/bin/bash
set -e

NAMESPACE="net-billing"

IP=$(kubectl get service invoice -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -z "$IP" || "$IP" == "None" ]]; then
    echo "❌ The 'invoice' Service has no ClusterIP"
    exit 1
fi

if ! kubectl exec -n "$NAMESPACE" billing -- \
        wget -qO- --timeout=8 "http://${IP}:80" 2>/dev/null | grep -qi "nginx\|<html"; then
    echo "❌ 'billing' still cannot reach the 'invoice' Service on port 80"
    exit 1
fi

echo "✅ 'billing' can reach the 'invoice' Service on port 80"
exit 0
