#!/bin/bash
set -e

NAMESPACE="quay-edge"
GATEWAY="quay-gw"
HOST="quay.harbor.local"

GW=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$GW" ]]; then
    echo "❌ Gateway '$GATEWAY' not found in '$NAMESPACE'"
    exit 1
fi

if [[ "$(echo "$GW" | jq -r '.spec.gatewayClassName')" != "harbor-gwc" ]]; then
    echo "❌ Gateway '$GATEWAY' does not use the GatewayClass harbor-gwc"
    exit 1
fi

HTTPS=$(echo "$GW" | jq -c '[.spec.listeners[] | select(.name == "https")][0]')
if [[ "$HTTPS" == "null" ]]; then
    echo "❌ Gateway '$GATEWAY' has no listener named https"
    exit 1
fi
if ! echo "$HTTPS" | jq -e --arg h "$HOST" '
        .protocol == "HTTPS" and .port == 443 and .hostname == $h
        and ((.tls.mode // "Terminate") == "Terminate")
        and ((.tls.certificateRefs // []) | length == 1)
        and (.tls.certificateRefs[0].name == "quay-tls")
        and ((.tls.certificateRefs[0].kind // "Secret") == "Secret")
        and ((.tls.certificateRefs[0].namespace // "quay-edge") == "quay-edge")' >/dev/null; then
    echo "❌ Listener https must be HTTPS on 443 for $HOST, terminating TLS with the Secret quay-tls: $HTTPS"
    exit 1
fi

HTTP=$(echo "$GW" | jq -c '[.spec.listeners[] | select(.name == "http")][0]')
if [[ "$HTTP" == "null" ]]; then
    echo "❌ Gateway '$GATEWAY' has no listener named http"
    exit 1
fi
if ! echo "$HTTP" | jq -e --arg h "$HOST" '.protocol == "HTTP" and .port == 80 and .hostname == $h' >/dev/null; then
    echo "❌ Listener http must be HTTP on 80 for $HOST: $HTTP"
    exit 1
fi

echo "✅ Gateway '$GATEWAY' has the https and http listeners"
exit 0
