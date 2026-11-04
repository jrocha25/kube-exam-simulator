#!/bin/bash
set -e

NAMESPACE="svc-telemetry"
SERVICE="telemetry"

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

TYPE=$(jq -r '.spec.type' <<<"$JSON")
if [[ "$TYPE" != "ClusterIP" ]]; then
    echo "❌ Service '$SERVICE' is of type $TYPE, expected ClusterIP"
    exit 1
fi

# targetPort is stored as it was written: an integer when numeric, a string
# when it names a container port. The question asks for the name.
WEB=$(jq -r '.spec.ports[]? | select(.port==80) | "\(.name // "") \(.targetPort)"' <<<"$JSON")
METRICS=$(jq -r '.spec.ports[]? | select(.port==9100) | "\(.name // "") \(.targetPort)"' <<<"$JSON")
if [[ "$WEB" != "web http" ]]; then
    echo "❌ Port 80 must be named 'web' and target the container port 'http' by name (found: ${WEB:-no port 80})"
    exit 1
fi
if [[ "$METRICS" != "metrics metrics" ]]; then
    echo "❌ Port 9100 must be named 'metrics' and target the container port 'metrics' by name (found: ${METRICS:-no port 9100})"
    exit 1
fi

SELECTOR=$(jq -c '.spec.selector // {}' <<<"$JSON")
LABELS=$(kubectl get deployment telemetry -n "$NAMESPACE" -o json 2>/dev/null | jq -c '.spec.template.metadata.labels')
MATCH=$(jq -n --argjson s "$SELECTOR" --argjson l "$LABELS" '($s | length) > 0 and ([$s | to_entries[] | $l[.key] == .value] | all)')
if [[ "$MATCH" != "true" ]]; then
    echo "❌ The Service selector $SELECTOR does not select the telemetry Pods (labels $LABELS)"
    exit 1
fi

echo "✅ Service '$SERVICE' exposes 80->http and 9100->metrics by name"
exit 0
