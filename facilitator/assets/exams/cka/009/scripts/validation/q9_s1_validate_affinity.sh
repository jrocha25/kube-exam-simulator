#!/bin/bash

set -e

# podAffinity defaults to the pod's OWN namespace, so a rule that names the
# collector's labels but not its namespace matches nothing and leaves every
# replica Pending. Either explicit form is accepted -- a "namespaces" list or a
# namespaceSelector -- because both are correct; the placement step then proves
# whichever one was written actually works.

NAMESPACE="sched-podaff"
INFRA_NS="sched-podaff-infra"
DEPLOYMENT="depot-agent"
TARGET="depot-telemetry"
TOPOLOGY_KEY="kubernetes.io/hostname"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json)

if [[ "$(echo "$SPEC" | jq '.spec.template.spec.affinity.podAntiAffinity // null')" != "null" ]]; then
    echo "❌ '$DEPLOYMENT' declares podAntiAffinity; this question asks for co-location, not separation"
    exit 1
fi

TERMS=$(echo "$SPEC" | jq '
    .spec.template.spec.affinity.podAffinity
    .requiredDuringSchedulingIgnoredDuringExecution // [] | length')
if [[ "$TERMS" -lt 1 ]]; then
    echo "❌ '$DEPLOYMENT' has no requiredDuringSchedulingIgnoredDuringExecution pod affinity"
    exit 1
fi

MATCH=$(echo "$SPEC" | jq -r --arg k "$TOPOLOGY_KEY" --arg t "$TARGET" --arg ns "$INFRA_NS" '
    [ .spec.template.spec.affinity.podAffinity
      .requiredDuringSchedulingIgnoredDuringExecution[]?
      | select(.topologyKey == $k)
      | select([ .labelSelector
                 | ((.matchLabels // {}) | to_entries[] | .value),
                   ((.matchExpressions // [])[] | (.values // [])[]) ] | index($t))
      | select(((.namespaces // []) | index($ns)) or (.namespaceSelector != null))
    ] | length')

if [[ "$MATCH" -lt 1 ]]; then
    echo "❌ No pod-affinity term selects '$TARGET' on '$TOPOLOGY_KEY' while naming the '$INFRA_NS' namespace"
    echo "   Pod affinity is scoped to this Deployment's own namespace unless it says otherwise."
    exit 1
fi

echo "✅ '$DEPLOYMENT' requires co-location with '$TARGET' in '$INFRA_NS' on '$TOPOLOGY_KEY'"
exit 0
