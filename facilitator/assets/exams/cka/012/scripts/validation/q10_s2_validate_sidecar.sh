#!/bin/bash
set -e

# Both init containers are asserted, in order, with restartPolicy on the right
# one. That matters for more than tidiness: the documentation's sidecar example is
# one regular container plus ONE init container carrying restartPolicy: Always,
# and with a name-only check that snippet would score this question with nothing
# but the names changed. A plain init container that has to finish first, followed
# by a sidecar that stays up, is a composition the docs never show in one block.

NAMESPACE="wl-shipper"
POD="trace-shipper"
FIRST="prepare-spool"
SIDECAR="log-forwarder"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

COUNT=$(jq '(.spec.initContainers // []) | length' <<<"$JSON")
ORDER=$(jq -r '[(.spec.initContainers // [])[].name] | join(",")' <<<"$JSON")

if [[ "$COUNT" != "2" ]]; then
    echo "❌ '$POD' has ${COUNT} init container(s), expected 2 ('${ORDER:-none}')"
    exit 1
fi
if [[ "$ORDER" != "${FIRST},${SIDECAR}" ]]; then
    echo "❌ '$POD' has init containers '${ORDER}', expected '${FIRST}' then '${SIDECAR}'"
    echo "   Init containers run in the order they are listed, and the spool has to exist first."
    exit 1
fi

SIDE_POLICY=$(jq -r --arg n "$SIDECAR" '[(.spec.initContainers // [])[] | select(.name == $n)][0].restartPolicy // ""' <<<"$JSON")
if [[ "$SIDE_POLICY" != "Always" ]]; then
    echo "❌ '${SIDECAR}' has restartPolicy '${SIDE_POLICY:-unset}', expected 'Always'"
    echo "   That field is what turns an init container into a native sidecar: without it the Pod"
    echo "   waits for it to finish, and it never does."
    exit 1
fi

FIRST_POLICY=$(jq -r --arg n "$FIRST" '[(.spec.initContainers // [])[] | select(.name == $n)][0].restartPolicy // ""' <<<"$JSON")
if [[ "$FIRST_POLICY" == "Always" ]]; then
    echo "❌ '${FIRST}' also carries restartPolicy: Always, so it never completes"
    echo "   It is supposed to be an ordinary init container."
    exit 1
fi

echo "✅ '${SIDECAR}' is a native sidecar and '${FIRST}' is a plain init container, in that order"
exit 0
