#!/bin/bash
set -e

NAMESPACE="svc-iptables"
SERVICE="apronctl"
POD="apronctl"

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json)

TYPE=$(jq -r '.spec.type // ""' <<<"$JSON")
if [[ "$TYPE" != "ClusterIP" ]]; then
    echo "❌ Service '$SERVICE' is of type '${TYPE}', expected 'ClusterIP'"
    exit 1
fi

if ! jq -e '(.spec.ports // []) | any(.port == 8080 and ((.targetPort == 80) or (.targetPort == "80")))' \
    <<<"$JSON" >/dev/null; then
    PORTS=$(jq -r '(.spec.ports // []) | map("\(.port)->\(.targetPort)") | join(", ")' <<<"$JSON")
    echo "❌ Service '$SERVICE' does not accept port 8080 and forward to 80 (found: ${PORTS:-none})"
    exit 1
fi

POD_IP=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$POD_IP" ]]; then
    echo "❌ Pod '$POD' has no IP address"
    exit 1
fi

# A Service with no endpoint is not exposing the Pod, whatever its selector says.
for _ in $(seq 1 8); do
    ADDRESSES=$(kubectl get endpointslices -n "$NAMESPACE" -l "kubernetes.io/service-name=${SERVICE}" \
        -o jsonpath='{range .items[*]}{range .endpoints[*]}{.addresses[0]}{"\n"}{end}{end}' 2>/dev/null || true)
    grep -qx "$POD_IP" <<<"$ADDRESSES" && break
    sleep 5
done
if ! grep -qx "$POD_IP" <<<"$ADDRESSES"; then
    echo "❌ Service '$SERVICE' has no endpoint pointing at the '$POD' Pod (${POD_IP})"
    exit 1
fi

echo "✅ Service '$SERVICE' exposes '$POD' on port 8080"
exit 0
