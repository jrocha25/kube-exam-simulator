#!/bin/bash
set -e

NAMESPACE="rbac-deploy"
ROLE="scaler"

if ! kubectl get role "$ROLE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Role '$ROLE' not found in namespace '$NAMESPACE'"
    exit 1
fi

RULES=$(kubectl get role "$ROLE" -n "$NAMESPACE" -o json)

has_rule() {
    local resource="$1" verb="$2"
    local found
    found=$(echo "$RULES" | jq --arg r "$resource" --arg v "$verb" '
        [.rules[]
         | select(((.apiGroups // []) | index("apps") or index("*")))
         | select(((.resources // []) | index($r) or index("*")))
         | select(((.verbs // []) | index($v) or index("*")))] | length')
    if [[ "$found" == "0" ]]; then
        echo "❌ Role '$ROLE' does not allow '$verb' on '$resource' in the 'apps' API group"
        exit 1
    fi
}

for verb in get patch update; do
    has_rule deployments/scale "$verb"
done
has_rule deployments get
has_rule deployments list

# The Deployment object itself must stay read only.
WRITE=$(echo "$RULES" | jq '[.rules[]
    | select(((.resources // []) | index("deployments") or index("*")))
    | select(((.verbs // []) | index("update") or index("patch") or index("delete") or index("create") or index("*")))] | length')
if [[ "$WRITE" != "0" ]]; then
    echo "❌ Role '$ROLE' grants write access to the Deployment object itself, not only to its scale subresource"
    exit 1
fi

echo "✅ Role '$ROLE' grants the scale subresource and read access to Deployments"
exit 0
