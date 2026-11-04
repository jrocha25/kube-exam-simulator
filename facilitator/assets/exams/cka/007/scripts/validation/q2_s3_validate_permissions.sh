#!/bin/bash
set -e

check() {
    local expected="$1" verb="$2" resource="$3"
    shift 3
    local answer
    answer=$(kubectl auth can-i "$verb" "$resource" "$@" 2>/dev/null || true)
    if [[ "$answer" != "$expected" ]]; then
        echo "❌ '$verb $resource' as [$*] returned '${answer:-<none>}', expected '$expected'"
        exit 1
    fi
}

# A member of the group is anyone impersonating it; the username itself is
# irrelevant to a Group subject.
check yes list  nodes              --as=someone --as-group=platform-auditors
check yes watch persistentvolumes  --as=someone --as-group=platform-auditors
check yes get   storageclasses     --as=someone --as-group=platform-auditors
check yes list  namespaces         --as=someone --as-group=platform-auditors

check yes list nodes --as=dana
check yes get  persistentvolumes --as=dana

# Nobody outside the grant may read the inventory.
check no list nodes --as=unrelated-person
check no list nodes --as=someone --as-group=some-other-team

echo "✅ The inventory grant reaches the group 'platform-auditors' and the user 'dana', and nobody else"
exit 0
