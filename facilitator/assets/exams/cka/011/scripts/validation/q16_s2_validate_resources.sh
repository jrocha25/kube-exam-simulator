#!/bin/bash
set -e

# Read from a Pod rather than the Deployment: a container that declares only
# limits has its requests defaulted to them by admission, which is a correct
# answer that the Deployment spec alone would not show.

NAMESPACE="qos-hangar"
DEPLOYMENT="hangar-ops"
CONTAINER="ops"
CPU="50m"
MEMORY="64Mi"

POD=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
    echo "❌ No running '$DEPLOYMENT' Pod found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json)

for field in requests limits; do
    GOT_CPU=$(jq -r --arg c "$CONTAINER" --arg f "$field" \
        '.spec.containers[] | select(.name==$c) | .resources[$f].cpu // ""' <<<"$JSON")
    GOT_MEM=$(jq -r --arg c "$CONTAINER" --arg f "$field" \
        '.spec.containers[] | select(.name==$c) | .resources[$f].memory // ""' <<<"$JSON")
    if [[ "$GOT_CPU" != "$CPU" ]]; then
        echo "❌ Container '$CONTAINER' has ${field}.cpu '${GOT_CPU:-unset}', expected '$CPU'"
        exit 1
    fi
    if [[ "$GOT_MEM" != "$MEMORY" ]]; then
        echo "❌ Container '$CONTAINER' has ${field}.memory '${GOT_MEM:-unset}', expected '$MEMORY'"
        exit 1
    fi
done

echo "✅ The container is configured with ${CPU} CPU and ${MEMORY} memory"
exit 0
