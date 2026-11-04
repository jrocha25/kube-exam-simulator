#!/bin/bash
set -e

CLUSTER_ROLE="deploy-manager"

if ! kubectl get clusterrole "$CLUSTER_ROLE" &> /dev/null; then
    echo "❌ ClusterRole '$CLUSTER_ROLE' not found"
    exit 1
fi

RULES=$(kubectl get clusterrole "$CLUSTER_ROLE" -o json)

has_rule() {
    local GROUP="$1" RESOURCE="$2" VERB="$3"
    echo "$RULES" | jq -e --arg g "$GROUP" --arg r "$RESOURCE" --arg v "$VERB" '
        [.rules // [] | .[]
          | select(((.apiGroups // []) | index($g)) != null or ((.apiGroups // []) | index("*")) != null)
          | select(((.resources // []) | index($r)) != null or ((.resources // []) | index("*")) != null)
          | select(((.verbs // []) | index($v)) != null or ((.verbs // []) | index("*")) != null)
        ] | length > 0' > /dev/null
}

for RESOURCE in deployments replicasets; do
    for VERB in get list watch create update patch delete; do
        if ! has_rule "apps" "$RESOURCE" "$VERB"; then
            echo "❌ ClusterRole '$CLUSTER_ROLE' does not allow '$VERB' on '$RESOURCE' in the 'apps' API group"
            exit 1
        fi
    done
done

for VERB in get list; do
    if ! has_rule "" "pods" "$VERB"; then
        echo "❌ ClusterRole '$CLUSTER_ROLE' does not allow '$VERB' on 'pods'"
        exit 1
    fi
done

echo "✅ ClusterRole '$CLUSTER_ROLE' grants the required permissions"
exit 0
