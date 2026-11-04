#!/bin/bash
set -e

USER="system:serviceaccount:rbac-broken:sync-agent"
NAMESPACE="rbac-broken"

for verb in get list watch update; do
    ANSWER=$(kubectl auth can-i "$verb" deployments.apps --as="$USER" -n "$NAMESPACE" 2>/dev/null || true)
    if [[ "$ANSWER" != "yes" ]]; then
        echo "❌ '$USER' cannot '$verb' deployments in '$NAMESPACE'"
        exit 1
    fi
done

echo "✅ '$USER' can get, list, watch and update Deployments in '$NAMESPACE'"
exit 0
