#!/bin/bash
set -e

check_denied() {
    local verb="$1" resource="$2"
    local answer
    answer=$(kubectl auth can-i "$verb" "$resource" --as=dana --as-group=platform-auditors 2>/dev/null || true)
    if [[ "$answer" == "yes" ]]; then
        echo "❌ The auditors can '$verb' '$resource'; the grant is not read only"
        exit 1
    fi
}

check_denied delete nodes
check_denied patch  nodes
check_denied create persistentvolumes
check_denied delete namespaces
check_denied get    secrets

echo "✅ The inventory grant is read only"
exit 0
