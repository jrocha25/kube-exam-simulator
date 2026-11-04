#!/bin/bash
set -e

CLUSTERROLE="monitoring-view"

if ! kubectl get clusterrole "$CLUSTERROLE" &> /dev/null; then
    echo "❌ ClusterRole '$CLUSTERROLE' not found"
    exit 1
fi

# The aggregation controller fills .rules in; give it a bounded moment to run.
for _ in $(seq 1 12); do
    RESOURCES=$(kubectl get clusterrole "$CLUSTERROLE" -o json | jq -r '[.rules[]? | (.resources // [])[]] | unique | join(",")')
    if [[ "$RESOURCES" == *"pods"* && "$RESOURCES" == *"nodes"* ]]; then
        break
    fi
    sleep 5
done

if [[ "$RESOURCES" != *"pods"* ]]; then
    echo "❌ '$CLUSTERROLE' has not aggregated any rule covering pods (resources: ${RESOURCES:-<none>})"
    exit 1
fi
if [[ "$RESOURCES" != *"nodes"* ]]; then
    echo "❌ '$CLUSTERROLE' has not aggregated any rule covering nodes (resources: ${RESOURCES:-<none>})"
    exit 1
fi

echo "✅ The aggregation controller populated '$CLUSTERROLE' from both contributor roles"
exit 0
