#!/bin/bash
set -e

NAMESPACE="rbac-tower"
SA="system:serviceaccount:rbac-tower:flightplan-writer"

for resource in configmaps secrets; do
    ANSWER=$(kubectl auth can-i create "$resource" -n "$NAMESPACE" --as="$SA" 2>/dev/null </dev/null || true)
    if [[ "$ANSWER" != "yes" ]]; then
        echo "❌ The account may not create ${resource} in '$NAMESPACE' (answer: ${ANSWER:-no})"
        exit 1
    fi
done

echo "✅ The account can create ConfigMaps and Secrets in '$NAMESPACE'"
exit 0
