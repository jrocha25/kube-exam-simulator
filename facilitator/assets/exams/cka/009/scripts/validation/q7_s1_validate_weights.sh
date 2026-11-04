#!/bin/bash

set -e

# Two competing weights is the graded idea. The documentation's example pairs one
# preferred term with a required one; this asserts the opposite shape, so a
# pasted snippet does not satisfy it.

NAMESPACE="sched-prefer"
DEPLOYMENT="tracking-api"
ZONE_KEY="topology.kubernetes.io/zone"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json)

COUNT=$(echo "$SPEC" | jq '
    .spec.template.spec.affinity.nodeAffinity
    .preferredDuringSchedulingIgnoredDuringExecution // [] | length')
if [[ "$COUNT" != "2" ]]; then
    echo "❌ Expected exactly 2 preferred node-affinity terms, found ${COUNT}"
    exit 1
fi

check_term() {
    local WEIGHT="$1" ZONE="$2" FOUND
    FOUND=$(echo "$SPEC" | jq --argjson w "$WEIGHT" --arg z "$ZONE" --arg k "$ZONE_KEY" '
        [ .spec.template.spec.affinity.nodeAffinity
          .preferredDuringSchedulingIgnoredDuringExecution[]?
          | select(.weight == $w)
          | select([ .preference.matchExpressions[]?
                     | select(.key == $k and .operator == "In")
                     | select((.values // []) | index($z)) ] | length > 0)
        ] | length')
    if [[ "$FOUND" -lt 1 ]]; then
        echo "❌ No preferred term with weight ${WEIGHT} selecting ${ZONE_KEY}=${ZONE}"
        exit 1
    fi
}

check_term 70 edge-1
check_term 30 edge-2

echo "✅ '$DEPLOYMENT' prefers edge-1 at weight 70 and edge-2 at weight 30"
exit 0
