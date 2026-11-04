#!/bin/bash
set -e

NAMESPACE="edge-tls"
GATEWAY="tls-gw"
SECRET="helioscale-tls"
HOSTNAME_VALUE="secure.helioscale.io"

if ! kubectl get gateway "$GATEWAY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o json)

CLASS=$(echo "$SPEC" | jq -r '.spec.gatewayClassName // empty')
if ! kubectl get gatewayclass "$CLASS" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' references the GatewayClass '${CLASS:-<none>}', which does not exist"
    exit 1
fi

LISTENER=$(echo "$SPEC" | jq '[.spec.listeners // [] | .[] | select(.name == "https")] | first // empty')
if [[ -z "$LISTENER" ]]; then
    echo "❌ Gateway '$GATEWAY' has no listener named 'https'"
    exit 1
fi

PORT=$(echo "$LISTENER" | jq -r '.port // empty')
PROTOCOL=$(echo "$LISTENER" | jq -r '.protocol // empty')
LISTENER_HOST=$(echo "$LISTENER" | jq -r '.hostname // empty')
MODE=$(echo "$LISTENER" | jq -r '.tls.mode // empty')
CERT=$(echo "$LISTENER" | jq -r '[.tls.certificateRefs // [] | .[] | select(.name != null) | .name] | first // empty')

if [[ "$PORT" != "443" ]]; then
    echo "❌ Incorrect listener port. Expected '443', got '${PORT:-<none>}'"
    exit 1
fi
if [[ "$PROTOCOL" != "HTTPS" ]]; then
    echo "❌ Incorrect listener protocol. Expected 'HTTPS', got '${PROTOCOL:-<none>}'"
    exit 1
fi
if [[ "$LISTENER_HOST" != "$HOSTNAME_VALUE" ]]; then
    echo "❌ Incorrect listener hostname. Expected '$HOSTNAME_VALUE', got '${LISTENER_HOST:-<none>}'"
    exit 1
fi
if [[ "$MODE" != "Terminate" ]]; then
    echo "❌ The listener must terminate TLS (tls.mode: '${MODE:-<none>}')"
    exit 1
fi
if [[ "$CERT" != "$SECRET" ]]; then
    echo "❌ The listener must reference the certificate Secret '$SECRET' (got: '${CERT:-<none>}')"
    exit 1
fi

echo "✅ Gateway '$GATEWAY' terminates TLS for '$HOSTNAME_VALUE' with the Secret '$SECRET'"
exit 0
