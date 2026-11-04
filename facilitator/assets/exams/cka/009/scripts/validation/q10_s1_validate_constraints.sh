#!/bin/bash

set -e

# Exactly two constraints, contrasting the hard and soft forms of
# whenUnsatisfiable. The documentation's example is a single block; a pasted
# snippet fails on the count alone.
#
# The labelSelector is graded too: one that matches nothing is satisfied
# everywhere and spreads nothing.

NAMESPACE="sched-spread"
DEPLOYMENT="parcel-tracker"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json)

COUNT=$(echo "$SPEC" | jq '.spec.template.spec.topologySpreadConstraints // [] | length')
if [[ "$COUNT" != "2" ]]; then
    echo "❌ Expected exactly 2 topologySpreadConstraints, found ${COUNT}"
    exit 1
fi

check_constraint() {
    local KEY="$1" ACTION="$2" FOUND
    FOUND=$(echo "$SPEC" | jq --arg k "$KEY" --arg a "$ACTION" '
        [ .spec.template.spec.topologySpreadConstraints[]?
          | select(.topologyKey == $k)
          | select(.maxSkew == 1)
          | select(.whenUnsatisfiable == $a)
          | select((.labelSelector.matchLabels.app // "") == "parcel-tracker")
        ] | length')
    if [[ "$FOUND" -lt 1 ]]; then
        echo "❌ No constraint with topologyKey '$KEY', maxSkew 1, whenUnsatisfiable '$ACTION'"
        echo "   and a labelSelector matching app=parcel-tracker"
        exit 1
    fi
}

check_constraint "topology.kubernetes.io/zone" "DoNotSchedule"
check_constraint "kubernetes.io/hostname" "ScheduleAnyway"

echo "✅ '$DEPLOYMENT' spreads hard across zones and softly across hosts"
exit 0
