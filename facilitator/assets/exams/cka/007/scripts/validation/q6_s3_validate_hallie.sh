#!/bin/bash
set -e

NAMESPACE="rbac-review"
SUBJECT="hallie"

allowed() {
    local verb=$1 resource=$2
    local out
    out=$(kubectl auth can-i "$verb" "$resource" -n "$NAMESPACE" --as="$SUBJECT" 2>/dev/null || true)
    grep -qx "yes" <<< "$out"
}

for resource in configmaps pods secrets; do
    for verb in get list watch create update patch delete; do
        if allowed "$verb" "$resource"; then
            echo "❌ User '$SUBJECT' can still '$verb' $resource in '$NAMESPACE' and must have no access at all"
            exit 1
        fi
    done
done

echo "✅ User '$SUBJECT' has no access in namespace '$NAMESPACE'"
exit 0
