#!/bin/bash
set -e

NAMESPACE="dns-alias"
POD="resolver"
CANARY="kubernetes.default.svc.cluster.local."

if ! kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ The '$POD' Pod is missing from namespace '$NAMESPACE'"
    exit 1
fi

READY=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "${READY:-0}" -lt 1 ]]; then
    echo "❌ CoreDNS has no ready replicas"
    exit 1
fi

EXPECTED=$(kubectl get service kubernetes -n default -o jsonpath='{.spec.clusterIP}')
for _ in $(seq 1 6); do
    OUT=$(kubectl exec -n "$NAMESPACE" "$POD" -- nslookup "$CANARY" 2>&1 || true)
    grep -q "$EXPECTED" <<<"$OUT" && break
    sleep 5
done
if ! grep -q "$EXPECTED" <<<"$OUT"; then
    echo "❌ Cluster DNS no longer resolves ${CANARY} -- the CoreDNS change broke ordinary names"
    exit 1
fi

echo "✅ Cluster DNS still resolves ordinary names"
exit 0
