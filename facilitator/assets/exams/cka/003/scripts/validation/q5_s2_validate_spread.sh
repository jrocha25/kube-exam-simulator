#!/bin/bash
set -e

NAMESPACE="spread-lab"
DEPLOYMENT="spread-web"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

COUNT=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '.spec.template.spec.topologySpreadConstraints // [] | length')
if [[ "$COUNT" != "1" ]]; then
    echo "❌ Expected exactly one topology spread constraint, found $COUNT"
    exit 1
fi

MAX_SKEW=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].maxSkew}')
if [[ "$MAX_SKEW" != "1" ]]; then
    echo "❌ Incorrect maxSkew. Expected '1', got '$MAX_SKEW'"
    exit 1
fi

TOPOLOGY_KEY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].topologyKey}')
if [[ "$TOPOLOGY_KEY" != "kubernetes.io/hostname" ]]; then
    echo "❌ Incorrect topologyKey. Expected 'kubernetes.io/hostname', got '$TOPOLOGY_KEY'"
    exit 1
fi

WHEN=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].whenUnsatisfiable}')
if [[ "$WHEN" != "ScheduleAnyway" ]]; then
    echo "❌ Incorrect whenUnsatisfiable. Expected 'ScheduleAnyway', got '$WHEN'"
    exit 1
fi

SELECTOR=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].labelSelector.matchLabels.app}')
if [[ "$SELECTOR" != "spread-web" ]]; then
    echo "❌ Topology spread labelSelector does not match app=spread-web (got: '$SELECTOR')"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' declares the required topology spread constraint"
exit 0
