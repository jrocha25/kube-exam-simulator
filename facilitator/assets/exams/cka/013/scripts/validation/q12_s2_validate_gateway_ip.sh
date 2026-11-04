#!/bin/bash
set -e

NAMESPACE="net-orbit"
SERVICE="orbit-gw"

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Service '$SERVICE' not found in '$NAMESPACE'"
    exit 1
fi

if [[ "$(echo "$JSON" | jq -r '.spec.clusterIP')" != "10.250.0.40" ]]; then
    echo "❌ '$SERVICE' has the ClusterIP $(echo "$JSON" | jq -r '.spec.clusterIP'), expected 10.250.0.40"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -c '.spec.selector')" != '{"app":"orbit"}' ]]; then
    echo "❌ '$SERVICE' does not select app=orbit"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -c '[.spec.ports[] | {port, targetPort}]')" != '[{"port":80,"targetPort":80}]' ]]; then
    echo "❌ '$SERVICE' does not expose port 80 to target port 80"
    exit 1
fi

echo "✅ '$SERVICE' has the ClusterIP 10.250.0.40"
exit 0
