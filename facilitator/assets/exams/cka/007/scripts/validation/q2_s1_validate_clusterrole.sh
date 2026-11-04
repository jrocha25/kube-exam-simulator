#!/bin/bash
set -e

CLUSTERROLE="infra-auditor"

if ! kubectl get clusterrole "$CLUSTERROLE" &> /dev/null; then
    echo "❌ ClusterRole '$CLUSTERROLE' not found"
    exit 1
fi

RULES=$(kubectl get clusterrole "$CLUSTERROLE" -o json)

for entry in "nodes:" "persistentvolumes:" "namespaces:" "storageclasses:storage.k8s.io"; do
    RESOURCE="${entry%%:*}"
    GROUP="${entry#*:}"
    MISSING=$(echo "$RULES" | jq -r --arg r "$RESOURCE" --arg g "$GROUP" '
        [.rules[]
         | select(((.apiGroups // []) | index($g) or index("*")))
         | select(((.resources // []) | index($r) or index("*")))
         | (.verbs // [])] | flatten | unique
        | if (index("*")) then [] else (["get","list","watch"] - .) end | join(",")')
    if [[ -n "$MISSING" ]]; then
        echo "❌ ClusterRole '$CLUSTERROLE' does not allow '$MISSING' on '$RESOURCE'"
        exit 1
    fi
done

echo "✅ ClusterRole '$CLUSTERROLE' allows get, list and watch on the four inventory resources"
exit 0
