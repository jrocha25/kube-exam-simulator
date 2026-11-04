#!/bin/bash
set -e

USER="system:serviceaccount:rbac-excess:backup-agent"

check() {
    local expected="$1" verb="$2" resource="$3"
    local answer
    answer=$(kubectl auth can-i "$verb" "$resource" --as="$USER" 2>/dev/null || true)
    if [[ "$answer" != "$expected" ]]; then
        echo "❌ '$verb $resource' returned '${answer:-<none>}', expected '$expected'"
        exit 1
    fi
}

check yes get  persistentvolumes
check yes list persistentvolumes
check no  delete persistentvolumes
check no  create persistentvolumes

echo "✅ 'backup-agent' can read PersistentVolumes cluster wide, and cannot change them"
exit 0
