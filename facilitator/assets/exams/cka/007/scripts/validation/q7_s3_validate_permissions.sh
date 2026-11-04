#!/bin/bash
set -e

USER="system:serviceaccount:rbac-probe:probe-agent"

# Non-resource URLs are probed by passing the path where a resource would go.
#
# Only some of these prove anything. Impersonation puts the subject in
# 'system:authenticated', which the built-in system:public-info-viewer and
# system:discovery bindings already grant '/healthz', '/livez', '/version' and
# '/apis'. '/metrics' is granted by no default binding, and neither is any
# subpath of '/healthz', so those two are what actually test the new grant.
check() {
    local expected="$1" verb="$2" target="$3"
    local answer
    answer=$(kubectl auth can-i "$verb" "$target" --as="$USER" 2>/dev/null || true)
    if [[ "$answer" != "$expected" ]]; then
        echo "❌ '$verb $target' returned '${answer:-<none>}', expected '$expected'"
        exit 1
    fi
}

# Discriminating: nothing but the new ClusterRole can allow these.
check yes get /metrics
check yes get /healthz/etcd

# Required by the question, and satisfied by the grant.
check yes get /healthz
check yes get /livez
check yes get /version

# The grant covers endpoints, not the API's resources.
check no list pods
check no get nodes
check no get secrets
check no list namespaces

echo "✅ 'probe-agent' can read the health and metrics endpoints and no API resources"
exit 0
