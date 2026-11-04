#!/bin/bash
set -e

NAMESPACE="net-orbit"
SERVICE="orbit-legacy"
BASELINE=/tmp/exam/q12/legacy.json

if [[ ! -s "$BASELINE" ]]; then
    echo "❌ Setup did not record orbit-legacy, so this step cannot be graded"
    exit 1
fi

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Service '$SERVICE' not found in '$NAMESPACE'"
    exit 1
fi

IP=$(echo "$JSON" | jq -r '.spec.clusterIP')
if [[ ! "$IP" =~ ^10\.250\.0\.[0-9]+$ ]]; then
    echo "❌ '$SERVICE' has the ClusterIP $IP, outside 10.250.0.0/24"
    exit 1
fi

CURRENT=$(echo "$JSON" | jq -c '{selector: .spec.selector, ports: [.spec.ports[] | {name, port, targetPort, protocol}]}')
if [[ "$(echo "$CURRENT" | jq -S -c .)" != "$(jq -S -c . "$BASELINE")" ]]; then
    echo "❌ '$SERVICE' selector or ports changed"
    echo "   now:  $CURRENT"
    echo "   was:  $(cat "$BASELINE")"
    exit 1
fi

echo "✅ '$SERVICE' moved to $IP with its selector and ports unchanged"
exit 0
