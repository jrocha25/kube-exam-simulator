#!/bin/bash
set -e

NAMESPACE="edge-migrate"
ROUTE="web-route"
GATEWAY="web-gw"
HOSTNAME_VALUE="www.helioscale.io"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json)

PARENT=$(echo "$SPEC" | jq --arg g "$GATEWAY" '[.spec.parentRefs // [] | .[] | select(.name == $g)] | length')
if [[ "$PARENT" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' does not reference the Gateway '$GATEWAY' as a parent"
    exit 1
fi

HOST=$(echo "$SPEC" | jq -r --arg h "$HOSTNAME_VALUE" '[.spec.hostnames // [] | .[] | select(. == $h)] | first // empty')
if [[ "$HOST" != "$HOSTNAME_VALUE" ]]; then
    echo "❌ HTTPRoute '$ROUTE' must serve the hostname '$HOSTNAME_VALUE'"
    exit 1
fi

check_path() {
    local PATH_VALUE="$1" SERVICE="$2"
    local FOUND
    FOUND=$(echo "$SPEC" | jq --arg p "$PATH_VALUE" --arg s "$SERVICE" '[.spec.rules // [] | .[]
        | select([(.matches // [])[] | select(.path.type == "PathPrefix" and .path.value == $p)] | length > 0)
        | select([(.backendRefs // [])[] | select(.name == $s and .port == 80)] | length > 0)] | length')
    if [[ "$FOUND" == "0" ]]; then
        echo "❌ HTTPRoute '$ROUTE' does not route the PathPrefix '$PATH_VALUE' to '$SERVICE' on port 80"
        exit 1
    fi
}

check_path "/catalog" "catalog-svc"
check_path "/profile" "profile-svc"

echo "✅ HTTPRoute '$ROUTE' reproduces the routing of the legacy Ingress"
exit 0
