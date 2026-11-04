#!/bin/bash
set -e

NAMESPACE="edge-tls"
ROUTE="secure-route"
GATEWAY="tls-gw"
HOSTNAME_VALUE="secure.helioscale.io"
SERVICE="secure-svc"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json)

PARENT=$(echo "$SPEC" | jq --arg g "$GATEWAY" '[.spec.parentRefs // [] | .[]
    | select(.name == $g and .sectionName == "https")] | length')
if [[ "$PARENT" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' must attach to the 'https' listener of '$GATEWAY' via sectionName"
    exit 1
fi

HOST=$(echo "$SPEC" | jq -r --arg h "$HOSTNAME_VALUE" '[.spec.hostnames // [] | .[] | select(. == $h)] | first // empty')
if [[ "$HOST" != "$HOSTNAME_VALUE" ]]; then
    echo "❌ HTTPRoute '$ROUTE' must serve the hostname '$HOSTNAME_VALUE'"
    exit 1
fi

RULE=$(echo "$SPEC" | jq --arg s "$SERVICE" '[.spec.rules // [] | .[]
    | select([(.matches // [])[] | select(.path.type == "PathPrefix" and .path.value == "/")] | length > 0)
    | select([(.backendRefs // [])[] | select(.name == $s and .port == 80)] | length > 0)] | length')
if [[ "$RULE" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' has no rule matching the PathPrefix '/' and routing to '$SERVICE' on port 80"
    exit 1
fi

ACCEPTED=""
for _ in $(seq 1 12); do
    ACCEPTED=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json \
        | jq -r '[.status.parents[]? | .conditions[]? | select(.type == "Accepted" and .status == "True")] | length' 2>/dev/null || true)
    if [[ -n "$ACCEPTED" ]] && [[ "$ACCEPTED" != "0" ]]; then
        break
    fi
    sleep 5
done

if [[ -z "$ACCEPTED" ]] || [[ "$ACCEPTED" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' was not accepted on the 'https' listener"
    exit 1
fi

echo "✅ HTTPRoute '$ROUTE' serves '$HOSTNAME_VALUE' through the 'https' listener"
exit 0
