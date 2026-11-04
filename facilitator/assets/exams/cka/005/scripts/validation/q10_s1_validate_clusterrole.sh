#!/bin/bash
set -e

CLUSTERROLE="pod-debugger"

if ! kubectl get clusterrole "$CLUSTERROLE" &> /dev/null; then
    echo "❌ ClusterRole '$CLUSTERROLE' not found"
    exit 1
fi

RULES=$(kubectl get clusterrole "$CLUSTERROLE" -o json)

has_rule() {
    local resource="$1" verb="$2"
    local count
    count=$(echo "$RULES" | jq -r --arg r "$resource" --arg v "$verb" \
        '[.rules[]? | select((.apiGroups // [""]) | (index("") or index("*"))) | select((.resources // []) | (index($r) or index("*"))) | select((.verbs // []) | (index($v) or index("*")))] | length')
    if [[ "$count" == "0" ]]; then
        echo "❌ '$CLUSTERROLE' does not allow '$verb' on '$resource'"
        exit 1
    fi
}

has_rule pods get
has_rule pods list
has_rule pods/log get
has_rule pods/exec create

echo "✅ ClusterRole '$CLUSTERROLE' grants the required debugging verbs"
exit 0
