#!/bin/bash
set -e

NAMESPACE="net-egress"
FQDN="backend.net-egress.svc.cluster.local"

CLUSTER_IP=$(kubectl get service backend -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
if [[ -z "$CLUSTER_IP" ]]; then
    echo "❌ Service 'backend' has no cluster IP"
    exit 1
fi

OUTPUT=$(kubectl exec frontend -n "$NAMESPACE" --request-timeout=60s -- \
    nslookup "$FQDN" 2>/dev/null || true)

if ! echo "$OUTPUT" | grep -q "$CLUSTER_IP"; then
    echo "❌ Pod 'frontend' cannot resolve '$FQDN' to $CLUSTER_IP"
    exit 1
fi

echo "✅ Pod 'frontend' resolves '$FQDN' to $CLUSTER_IP"
exit 0
