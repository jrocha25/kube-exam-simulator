#!/bin/bash
set -e

NAMESPACE="net-vault"
SLICE="vault-proxy-1"

JSON=$(kubectl get endpointslice "$SLICE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ EndpointSlice '$SLICE' not found in '$NAMESPACE'"
    exit 1
fi

if [[ "$(echo "$JSON" | jq -r '.metadata.labels["kubernetes.io/service-name"] // empty')" != "vault-proxy" ]]; then
    echo "❌ '$SLICE' is not linked to the Service vault-proxy"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -r '.metadata.labels["endpointslice.kubernetes.io/managed-by"] // empty')" != "staff.ck-x.io" ]]; then
    echo "❌ '$SLICE' is not labelled managed-by staff.ck-x.io"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -r '.addressType')" != "IPv4" ]]; then
    echo "❌ '$SLICE' does not hold IPv4 addresses"
    exit 1
fi

PORTS=$(echo "$JSON" | jq -c '[.ports[]? | {name, port, protocol: (.protocol // "TCP")}] | sort_by(.name)')
if [[ "$PORTS" != '[{"name":"api","port":8080,"protocol":"TCP"},{"name":"metrics","port":9100,"protocol":"TCP"}]' ]]; then
    echo "❌ '$SLICE' ports are $PORTS; they must be api 8080 and metrics 9100, named after the Service's ports"
    exit 1
fi

# Recomputed live, so the slice has to name the Pods' current addresses.
IP_A=$(kubectl get pod vault-a -n net-vault-backend -o jsonpath='{.status.podIP}')
IP_B=$(kubectl get pod vault-b -n net-vault-backend -o jsonpath='{.status.podIP}')

# A missing "ready" condition means ready. Not jq's "//": it treats false as missing too.
ready_of() {
    echo "$JSON" | jq -r --arg ip "$1" '[.endpoints[]? | select(.addresses | index($ip))
        | if .conditions.ready == null then true else .conditions.ready end] | if length == 0 then "missing" else (.[0] | tostring) end'
}
READY_A=$(ready_of "$IP_A")
READY_B=$(ready_of "$IP_B")
COUNT=$(echo "$JSON" | jq '[.endpoints[]?.addresses[]] | length')

if [[ "$READY_A" != "true" ]]; then
    echo "❌ vault-a ($IP_A) is $READY_A in the slice: it must be listed and ready"
    exit 1
fi
if [[ "$READY_B" != "false" ]]; then
    echo "❌ vault-b ($IP_B) is $READY_B in the slice: it must be listed and marked not ready"
    exit 1
fi
if [[ "$COUNT" != "2" ]]; then
    echo "❌ '$SLICE' lists $COUNT addresses, expected exactly vault-a and vault-b"
    exit 1
fi

echo "✅ '$SLICE' lists vault-a ready and vault-b not ready, on the Service's named ports"
exit 0
