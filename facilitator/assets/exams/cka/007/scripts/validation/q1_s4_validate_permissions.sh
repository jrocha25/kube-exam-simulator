#!/bin/bash
set -e

NAMESPACE="rbac-report"
USER="system:serviceaccount:rbac-report:report-reader"

# "can-i get configmaps/app-settings" is the positional resource/resourceName
# form, which is exactly what a resourceNames grant has to be probed with.
check() {
    local expected="$1" verb="$2" target="$3"
    local answer
    answer=$(kubectl auth can-i "$verb" "$target" --as="$USER" -n "$NAMESPACE" 2>/dev/null || true)
    if [[ "$answer" != "$expected" ]]; then
        echo "❌ '$verb $target' in '$NAMESPACE' returned '${answer:-<none>}', expected '$expected'"
        exit 1
    fi
}

check yes get configmaps/app-settings
check yes get configmaps/feature-flags
check no  get configmaps/billing-secrets
check no  list configmaps
check no  delete configmaps/app-settings
check yes get pods
check yes list pods

echo "✅ 'report-reader' can read only the two approved ConfigMaps, and cannot list the rest"
exit 0
