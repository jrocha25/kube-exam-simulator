#!/bin/bash
set -e

NAMESPACE="edge-team"
ROUTE="team-route"

ACCEPTED=""
for _ in $(seq 1 12); do
    ACCEPTED=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json 2>/dev/null \
        | jq -r '[.status.parents[]? | select(.parentRef.name=="platform-gw") | .conditions[]? | select(.type=="Accepted") | .status][0] // empty')
    if [[ "$ACCEPTED" == "True" ]]; then
        break
    fi
    sleep 5
done

if [[ "$ACCEPTED" != "True" ]]; then
    echo "❌ '$ROUTE' reports Accepted='${ACCEPTED:-<none>}' for 'platform-gw'"
    exit 1
fi

RESOLVED=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json \
    | jq -r '[.status.parents[]? | select(.parentRef.name=="platform-gw") | .conditions[]? | select(.type=="ResolvedRefs") | .status][0] // empty')
if [[ "$RESOLVED" != "True" ]]; then
    echo "❌ '$ROUTE' reports ResolvedRefs='${RESOLVED:-<none>}'"
    exit 1
fi

echo "✅ '$ROUTE' is attached to the Gateway in the platform namespace"
exit 0
