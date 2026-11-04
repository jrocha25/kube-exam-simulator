#!/bin/bash
set -e

NAMESPACE="rbac-review"
GROUP="legacy-operators"
# Any user name works: the grant under test is the Group subject, and the user
# below is bound to nothing of its own.
PROBE_USER="rbac-review-probe"

allowed() {
    local verb=$1 resource=$2
    local out
    out=$(kubectl auth can-i "$verb" "$resource" -n "$NAMESPACE" \
              --as="$PROBE_USER" --as-group="$GROUP" 2>/dev/null || true)
    grep -qx "yes" <<< "$out"
}

for verb in get list watch; do
    if ! allowed "$verb" pods; then
        echo "❌ Group '$GROUP' cannot '$verb' pods in '$NAMESPACE' and must be able to"
        exit 1
    fi
done

for verb in get list watch create update delete; do
    if allowed "$verb" configmaps; then
        echo "❌ Group '$GROUP' can still '$verb' configmaps in '$NAMESPACE' and must have no ConfigMap access"
        exit 1
    fi
done

echo "✅ Group '$GROUP' reads Pods in '$NAMESPACE' and has no ConfigMap access"
exit 0
