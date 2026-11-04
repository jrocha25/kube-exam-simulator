#!/bin/bash
set -e

USER="system:serviceaccount:rbac-broken:sync-agent"

for resource in deployments.apps pods; do
    ANSWER=$(kubectl auth can-i update "$resource" --as="$USER" -n rbac-broken-staging 2>/dev/null || true)
    if [[ "$ANSWER" == "yes" ]]; then
        echo "❌ '$USER' can update '$resource' in 'rbac-broken-staging'; the grant leaked"
        exit 1
    fi
done

ANSWER=$(kubectl auth can-i list pods --as="$USER" -n rbac-broken-staging 2>/dev/null || true)
if [[ "$ANSWER" == "yes" ]]; then
    echo "❌ '$USER' can list Pods in 'rbac-broken-staging'; the grant leaked"
    exit 1
fi

echo "✅ '$USER' has no access outside the 'rbac-broken' namespace"
exit 0
