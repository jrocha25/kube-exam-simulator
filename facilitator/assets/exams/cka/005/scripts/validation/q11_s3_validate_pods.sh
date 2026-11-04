#!/bin/bash
set -e

USER="system:serviceaccount:rbac-broken:sync-agent"
NAMESPACE="rbac-broken"

for verb in get list; do
    ANSWER=$(kubectl auth can-i "$verb" pods --as="$USER" -n "$NAMESPACE" 2>/dev/null || true)
    if [[ "$ANSWER" != "yes" ]]; then
        echo "❌ '$USER' cannot '$verb' pods in '$NAMESPACE'"
        exit 1
    fi
done

echo "✅ '$USER' can get and list Pods in '$NAMESPACE'"
exit 0
