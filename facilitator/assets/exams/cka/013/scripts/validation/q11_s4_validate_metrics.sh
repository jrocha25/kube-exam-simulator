#!/bin/bash
set -e

NAMESPACE="net-vault"
SERVICE="vault-proxy"

IP=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -z "$IP" || "$IP" == "None" ]]; then
    echo "❌ Service '$SERVICE' not found or has no ClusterIP"
    exit 1
fi

OUT=$(kubectl exec -n "$NAMESPACE" vault-client -- wget -qO- -T 3 "http://$IP:9100/metrics" 2>/dev/null || true)
if ! echo "$OUT" | grep -q '^vault_up{member="vault-a"} 1$'; then
    echo "❌ $SERVICE:9100 did not serve vault-a's metrics"
    exit 1
fi

echo "✅ $SERVICE:9100 answers"
exit 0
