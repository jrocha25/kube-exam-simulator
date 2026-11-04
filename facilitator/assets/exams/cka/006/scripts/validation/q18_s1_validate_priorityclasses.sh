#!/bin/bash
set -e

check_pc() {
    local name="$1" value="$2"
    local json
    json=$(kubectl get priorityclass "$name" -o json 2>/dev/null || true)
    if [[ -z "$json" ]]; then
        echo "❌ PriorityClass '$name' not found"
        return 1
    fi
    local got
    got=$(jq -r '.value' <<<"$json")
    if [[ "$got" != "$value" ]]; then
        echo "❌ PriorityClass '$name' has value $got, expected $value"
        return 1
    fi
    local default
    default=$(jq -r '.globalDefault // false' <<<"$json")
    if [[ "$default" == "true" ]]; then
        echo "❌ PriorityClass '$name' is the global default; neither class may be"
        return 1
    fi
    return 0
}

check_pc batch-low 10000 || exit 1
check_pc critical-high 100000 || exit 1

echo "✅ Both PriorityClasses exist with the required values and neither is the global default"
exit 0
