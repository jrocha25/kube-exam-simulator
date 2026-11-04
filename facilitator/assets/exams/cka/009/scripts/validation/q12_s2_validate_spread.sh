#!/bin/bash

set -e

# ScheduleAnyway, not DoNotSchedule. Two hard constraints on a three node cluster
# leave no slack, and the question is about delivering policy through Kustomize
# rather than about wedging the scheduler.

NAMESPACE="kustom-sched"
DEPLOYMENT="freight-api"
OVERLAY="/tmp/exam/q12/overlays/prod"
ZONE_KEY="topology.kubernetes.io/zone"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

MATCH=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq --arg k "$ZONE_KEY" '
    [ .spec.template.spec.topologySpreadConstraints[]?
      | select(.topologyKey == $k)
      | select(.maxSkew == 1)
      | select(.whenUnsatisfiable == "ScheduleAnyway")
      | select((.labelSelector.matchLabels.app // "") == "freight-api")
    ] | length')

if [[ "$MATCH" -lt 1 ]]; then
    echo "❌ No topologySpreadConstraint on '$ZONE_KEY' with maxSkew 1, ScheduleAnyway"
    echo "   and a labelSelector matching app=freight-api"
    exit 1
fi

if ! grep -rqs "topologySpreadConstraints" "$OVERLAY"; then
    echo "❌ 'topologySpreadConstraints' does not appear in '$OVERLAY'; it must come from the overlay"
    exit 1
fi

echo "✅ The overlay adds a zone spread constraint with maxSkew 1 and ScheduleAnyway"
exit 0
