#!/bin/bash
set -e

NAMESPACE="rbac-report"
ROLE="config-reader"

if ! kubectl get role "$ROLE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Role '$ROLE' not found in namespace '$NAMESPACE'"
    exit 1
fi

RULES=$(kubectl get role "$ROLE" -n "$NAMESPACE" -o json)

# Every rule that reaches configmaps must be restricted by resourceNames; one
# unrestricted rule would hand over the whole namespace's configuration.
UNRESTRICTED=$(echo "$RULES" | jq '[.rules[]
    | select(((.apiGroups // []) | index("") or index("*")) and ((.resources // []) | index("configmaps") or index("*")))
    | select((.resourceNames // []) | length == 0)] | length')
if [[ "$UNRESTRICTED" != "0" ]]; then
    echo "❌ Role '$ROLE' has $UNRESTRICTED configmaps rule(s) with no resourceNames; the grant is not restricted to named objects"
    exit 1
fi

NAMES=$(echo "$RULES" | jq -r '[.rules[]
    | select(((.resources // []) | index("configmaps")))
    | (.resourceNames // [])[]] | unique | join(",")')
if [[ "$NAMES" != "app-settings,feature-flags" ]]; then
    echo "❌ Role '$ROLE' names the configmaps '${NAMES:-<none>}', expected 'app-settings,feature-flags'"
    exit 1
fi

GET=$(echo "$RULES" | jq '[.rules[]
    | select(((.resources // []) | index("configmaps")))
    | select(((.verbs // []) | index("get") or index("*")))] | length')
if [[ "$GET" == "0" ]]; then
    echo "❌ Role '$ROLE' does not allow 'get' on the named configmaps"
    exit 1
fi

echo "✅ Role '$ROLE' allows 'get' on only the two named ConfigMaps"
exit 0
