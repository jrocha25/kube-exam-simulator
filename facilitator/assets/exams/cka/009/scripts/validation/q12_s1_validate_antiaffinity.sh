#!/bin/bash

set -e

# The rule itself is the classic one; the graded novelty is where it came from.
# The base is off limits and checked separately, so the rule has to be in the
# overlay -- which is also what stops a hand-written Deployment applied straight
# from the shell satisfying this question.

NAMESPACE="kustom-sched"
DEPLOYMENT="freight-api"
OVERLAY="/tmp/exam/q12/overlays/prod"
TOPOLOGY_KEY="kubernetes.io/hostname"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

MATCH=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq --arg k "$TOPOLOGY_KEY" '
    [ .spec.template.spec.affinity.podAntiAffinity
      .requiredDuringSchedulingIgnoredDuringExecution[]?
      | select(.topologyKey == $k)
      | select([ .labelSelector
                 | ((.matchLabels // {}) | to_entries[] | .value),
                   ((.matchExpressions // [])[] | (.values // [])[]) ] | index("freight-api"))
    ] | length')

if [[ "$MATCH" -lt 1 ]]; then
    echo "❌ No required pod anti-affinity on '$TOPOLOGY_KEY' selecting app=freight-api"
    exit 1
fi

if [[ ! -d "$OVERLAY" ]]; then
    echo "❌ Overlay directory '$OVERLAY' does not exist"
    exit 1
fi

if ! grep -rqs "podAntiAffinity" "$OVERLAY"; then
    echo "❌ 'podAntiAffinity' does not appear in '$OVERLAY'; the rule must come from the overlay"
    exit 1
fi

echo "✅ The overlay adds a required anti-affinity on '$TOPOLOGY_KEY' selecting app=freight-api"
exit 0
