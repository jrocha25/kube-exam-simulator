#!/bin/bash
set -e

NAMESPACE="svc-telemetry"
SERVICE="telemetry"

CLUSTER_IP=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -z "$CLUSTER_IP" || "$CLUSTER_IP" == "None" ]]; then
    echo "❌ Service '$SERVICE' has no cluster IP"
    exit 1
fi

for port in 80 9100; do
    READY=$(kubectl get endpointslice -n "$NAMESPACE" -l "kubernetes.io/service-name=$SERVICE" -o json 2>/dev/null \
        | jq --argjson p "$port" '[.items[] | select(.ports[]?.port == $p) | .endpoints[]? | select(.conditions.ready == true)] | length')
    if [[ "${READY:-0}" -lt 1 ]]; then
        echo "❌ No ready endpoints behind port $port of '$SERVICE'"
        exit 1
    fi
done

# Probe from a Pod the question already has -- the exporter container's busybox
# ships wget -- rather than one this script would create.
POD=$(kubectl get pods -n "$NAMESPACE" -l app=telemetry --field-selector status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
    echo "❌ No Running telemetry Pod to probe from"
    exit 1
fi

for _ in $(seq 1 6); do
    OK=yes
    kubectl exec -n "$NAMESPACE" "$POD" -c exporter -- wget -qO- -T 4 "http://${CLUSTER_IP}:80/" >/dev/null 2>&1 || OK=no
    kubectl exec -n "$NAMESPACE" "$POD" -c exporter -- wget -qO- -T 4 "http://${CLUSTER_IP}:9100/metrics" 2>/dev/null | grep -q telemetry_up || OK=no
    [[ "$OK" == yes ]] && break
    sleep 5
done
if [[ "$OK" != yes ]]; then
    echo "❌ ${CLUSTER_IP}:80 and/or ${CLUSTER_IP}:9100 do not answer from inside the namespace"
    exit 1
fi

echo "✅ Both ports of '$SERVICE' have ready endpoints and answer at $CLUSTER_IP"
exit 0
