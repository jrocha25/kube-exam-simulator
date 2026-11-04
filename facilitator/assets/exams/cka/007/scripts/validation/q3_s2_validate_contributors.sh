#!/bin/bash
set -e

LABEL_KEY="rbac.ck-x.io/aggregate-to-monitoring"

has_rule() {
    local role="$1" group="$2" resource="$3" verb="$4"
    local found
    found=$(kubectl get clusterrole "$role" -o json | jq --arg g "$group" --arg r "$resource" --arg v "$verb" '
        [.rules[]
         | select(((.apiGroups // []) | index($g) or index("*")))
         | select(((.resources // []) | index($r) or index("*")))
         | select(((.verbs // []) | index($v) or index("*")))] | length')
    if [[ "$found" == "0" ]]; then
        echo "❌ ClusterRole '$role' does not allow '$verb' on '$resource'"
        exit 1
    fi
}

for role in monitoring-pods monitoring-nodes; do
    if ! kubectl get clusterrole "$role" &> /dev/null; then
        echo "❌ ClusterRole '$role' not found"
        exit 1
    fi
    VALUE=$(kubectl get clusterrole "$role" -o json | jq -r '.metadata.labels["rbac.ck-x.io/aggregate-to-monitoring"] // ""')
    if [[ "$VALUE" != "true" ]]; then
        echo "❌ ClusterRole '$role' is not labelled '$LABEL_KEY=true' (found '${VALUE:-<none>}'), so it is never aggregated"
        exit 1
    fi
done

for verb in get list watch; do
    has_rule monitoring-pods "" pods "$verb"
    has_rule monitoring-nodes "" nodes "$verb"
done
has_rule monitoring-pods "" pods/log get
has_rule monitoring-nodes "" nodes/metrics get

echo "✅ Both contributor ClusterRoles carry the aggregation label and the required rules"
exit 0
