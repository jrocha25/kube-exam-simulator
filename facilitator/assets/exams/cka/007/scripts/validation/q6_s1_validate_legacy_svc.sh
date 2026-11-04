#!/bin/bash
set -e

NAMESPACE="rbac-review"
SUBJECT="system:serviceaccount:rbac-review:legacy-svc"

allowed() {
    local verb=$1 resource=$2
    local out
    out=$(kubectl auth can-i "$verb" "$resource" -n "$NAMESPACE" --as="$SUBJECT" 2>/dev/null || true)
    grep -qx "yes" <<< "$out"
}

if ! kubectl get serviceaccount legacy-svc -n "$NAMESPACE" &> /dev/null; then
    echo "❌ ServiceAccount 'legacy-svc' not found in namespace '$NAMESPACE'"
    exit 1
fi

for verb in get list update; do
    if ! allowed "$verb" configmaps; then
        echo "❌ 'legacy-svc' cannot '$verb' configmaps in '$NAMESPACE' and must be able to"
        exit 1
    fi
done

for verb in create delete; do
    if allowed "$verb" configmaps; then
        echo "❌ 'legacy-svc' can still '$verb' configmaps in '$NAMESPACE' and must not be able to"
        exit 1
    fi
done

echo "✅ 'legacy-svc' reads and updates ConfigMaps in '$NAMESPACE' but can no longer create or delete them"
exit 0
