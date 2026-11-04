#!/bin/bash
set -e

NAMESPACE="tally"
SERVICE="tally-board-np"

SVC=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$SVC" ]]; then
    echo "❌ Service '$SERVICE' not found in '$NAMESPACE'"
    exit 1
fi

if ! echo "$SVC" | jq -e '.spec.type == "NodePort"
        and (.spec.ports | length) == 1
        and .spec.ports[0].port == 80
        and .spec.ports[0].targetPort == "http"
        and .spec.ports[0].nodePort == 30814
        and ((.spec.ports[0].protocol // "TCP") == "TCP")' >/dev/null; then
    echo "❌ '$SERVICE' must be a NodePort Service with one port: 80 -> targetPort http, nodePort 30814: $(echo "$SVC" | jq -c '.spec | {type, ports}')"
    exit 1
fi

if [[ "$(echo "$SVC" | jq -c '.spec.selector')" != '{"app":"tally-board"}' ]]; then
    echo "❌ '$SERVICE' must select the Pods of tally-board (app=tally-board) and nothing narrower"
    exit 1
fi

COUNT=0
for _ in $(seq 1 6); do
    COUNT=$(kubectl get endpointslices -n "$NAMESPACE" -l kubernetes.io/service-name="$SERVICE" -o json \
        | jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length')
    [[ "$COUNT" == "2" ]] && break
    sleep 5
done
if [[ "$COUNT" != "2" ]]; then
    echo "❌ '$SERVICE' has $COUNT ready endpoints, expected 2"
    exit 1
fi

echo "✅ '$SERVICE' exposes tally-board on nodePort 30814 with 2 ready endpoints"
exit 0
