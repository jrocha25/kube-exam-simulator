#!/bin/bash
set -e

NAMESPACE="quay-edge"
ROUTE="quay-web"
HOST="quay.harbor.local"

RT=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$RT" ]]; then
    echo "❌ HTTPRoute '$ROUTE' not found in '$NAMESPACE'"
    exit 1
fi

if ! echo "$RT" | jq -e '(.spec.parentRefs | length) == 1
        and .spec.parentRefs[0].name == "quay-gw"
        and .spec.parentRefs[0].sectionName == "https"
        and ((.spec.parentRefs[0].namespace // "quay-edge") == "quay-edge")' >/dev/null; then
    echo "❌ HTTPRoute '$ROUTE' must attach to the https listener of quay-gw only"
    exit 1
fi

if [[ "$(echo "$RT" | jq -c '.spec.hostnames')" != "[\"$HOST\"]" ]]; then
    echo "❌ HTTPRoute '$ROUTE' must serve exactly the hostname $HOST"
    exit 1
fi

# One rule per Ingress path: the exact health path to quay-status:8080, and the
# prefix / to quay-web:80. jq walks every match of every rule.
rule_ok() {
    echo "$RT" | jq -e --arg type "$1" --arg path "$2" --arg svc "$3" --argjson port "$4" '
        [.spec.rules[]
         | select(any(.matches[]?; (.path.type // "PathPrefix") == $type and (.path.value // "/") == $path))
         | select((.backendRefs | length) == 1
                  and .backendRefs[0].name == $svc and .backendRefs[0].port == $port)]
        | length >= 1' >/dev/null
}

if ! rule_ok Exact /healthz/berths quay-status 8080; then
    echo "❌ HTTPRoute '$ROUTE' has no Exact /healthz/berths rule sending traffic to quay-status:8080"
    exit 1
fi
if ! rule_ok PathPrefix / quay-web 80; then
    echo "❌ HTTPRoute '$ROUTE' has no PathPrefix / rule sending traffic to quay-web:80"
    exit 1
fi

echo "✅ HTTPRoute '$ROUTE' reproduces both Ingress paths on the https listener"
exit 0
