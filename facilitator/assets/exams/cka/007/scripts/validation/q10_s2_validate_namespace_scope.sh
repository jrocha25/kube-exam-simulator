#!/bin/bash
set -e

NAMESPACE="rbac-excess"
USER="system:serviceaccount:rbac-excess:backup-agent"

check() {
    local expected="$1" verb="$2" resource="$3" namespace="$4"
    local answer
    answer=$(kubectl auth can-i "$verb" "$resource" --as="$USER" -n "$namespace" 2>/dev/null || true)
    if [[ "$answer" != "$expected" ]]; then
        echo "❌ '$verb $resource' in '$namespace' returned '${answer:-<none>}', expected '$expected'"
        exit 1
    fi
}

# What the backup job still needs.
check yes get  pods                   "$NAMESPACE"
check yes list pods                   "$NAMESPACE"
check yes get  persistentvolumeclaims "$NAMESPACE"
check yes list persistentvolumeclaims "$NAMESPACE"

# ...and nothing more, in its own namespace or anyone else's.
check no delete pods                   "$NAMESPACE"
check no create pods                   "$NAMESPACE"
check no delete persistentvolumeclaims "$NAMESPACE"
check no list   pods                   default
check no list   pods                   kube-system

echo "✅ 'backup-agent' reads Pods and claims in '$NAMESPACE' only"
exit 0
