#!/bin/bash
set -e

NAMESPACE="net-vault"
SERVICE="vault-proxy"

IP=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -z "$IP" || "$IP" == "None" ]]; then
    echo "❌ Service '$SERVICE' not found or has no ClusterIP"
    exit 1
fi

# Five in a row: with vault-b wrongly ready, kube-proxy would split traffic and
# the chance of five vault-a answers in a row is 1 in 32.
ANSWERS=$(kubectl exec -n "$NAMESPACE" vault-client -- sh -c \
    "for i in 1 2 3 4 5; do wget -qO- -T 3 http://$IP:80/ || echo FAILED; done" 2>/dev/null || true)
if [[ "$(echo "$ANSWERS" | grep -c '^vault-a$')" != "5" ]]; then
    echo "❌ Requests to $SERVICE:80 were answered by: $(echo "$ANSWERS" | tr '\n' ' ')"
    exit 1
fi

echo "✅ Every request to $SERVICE:80 was answered by vault-a"
exit 0
