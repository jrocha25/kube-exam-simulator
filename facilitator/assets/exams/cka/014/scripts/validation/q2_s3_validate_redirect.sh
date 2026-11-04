#!/bin/bash
set -e

NAMESPACE="quay-edge"
ROUTE="quay-redirect"
HOST="quay.harbor.local"

RT=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$RT" ]]; then
    echo "❌ HTTPRoute '$ROUTE' not found in '$NAMESPACE'"
    exit 1
fi

if ! echo "$RT" | jq -e '(.spec.parentRefs | length) == 1
        and .spec.parentRefs[0].name == "quay-gw"
        and .spec.parentRefs[0].sectionName == "http"' >/dev/null; then
    echo "❌ HTTPRoute '$ROUTE' must attach to the http listener of quay-gw only"
    exit 1
fi

if ! echo "$RT" | jq -e --arg h "$HOST" '(.spec.hostnames // [$h]) == [$h]' >/dev/null; then
    echo "❌ HTTPRoute '$ROUTE' must not serve any hostname other than $HOST"
    exit 1
fi

if ! echo "$RT" | jq -e '
        (.spec.rules | length) >= 1
        and all(.spec.rules[];
            ((.backendRefs // []) | length) == 0
            and any(.filters[]?; .type == "RequestRedirect"
                and .requestRedirect.scheme == "https"
                and .requestRedirect.statusCode == 301))' >/dev/null; then
    echo "❌ Every rule of '$ROUTE' must redirect to https with a 301 and send traffic to no backend"
    exit 1
fi

echo "✅ HTTPRoute '$ROUTE' redirects plain HTTP to https with a 301"
exit 0
