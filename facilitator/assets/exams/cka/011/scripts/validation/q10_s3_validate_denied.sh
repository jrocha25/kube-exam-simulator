#!/bin/bash
set -e

# "Only create" means every other verb on the same two resources is refused, and
# nothing else in the namespace is reachable at all. A "list" probe is the
# honest way to show a grant is narrow, because resourceNames cannot restrict
# list in the first place.

NAMESPACE="rbac-tower"
SA="system:serviceaccount:rbac-tower:flightplan-writer"

check_denied() {
    local verb="$1" resource="$2"
    local answer
    answer=$(kubectl auth can-i "$verb" "$resource" -n "$NAMESPACE" --as="$SA" 2>/dev/null </dev/null || true)
    if [[ "$answer" == "yes" ]]; then
        echo "❌ The account may '${verb} ${resource}' in '$NAMESPACE', which it must not"
        return 1
    fi
    return 0
}

# Guarded on the account existing. "can-i" answers "no" for a ServiceAccount
# that was never created, so without this the whole step passes on an untouched
# namespace -- it was worth 2 marks of a 7/100 unsolved floor until this guard
# was added.
for kind in serviceaccount role rolebinding; do
    if ! kubectl get "$kind" flightplan-writer -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "❌ ${kind^} 'flightplan-writer' does not exist in '$NAMESPACE', so there is nothing to have restricted"
        exit 1
    fi
done

# The account also has to be able to do the two things it is for; otherwise a
# namespace where it is denied everything would satisfy "cannot do anything else".
for resource in configmaps secrets; do
    ALLOWED=$(kubectl auth can-i create "$resource" -n "$NAMESPACE" --as="$SA" 2>/dev/null </dev/null || true)
    if [[ "$ALLOWED" != "yes" ]]; then
        echo "❌ The account cannot create ${resource}, so its permissions are not merely narrow -- they are absent"
        exit 1
    fi
done

check_denied get    configmaps || exit 1
check_denied list   configmaps || exit 1
check_denied update configmaps || exit 1
check_denied delete configmaps || exit 1
check_denied get    secrets    || exit 1
check_denied list   secrets    || exit 1
check_denied delete secrets    || exit 1
check_denied create pods       || exit 1
check_denied list   pods       || exit 1

echo "✅ The account cannot do anything in '$NAMESPACE' beyond creating ConfigMaps and Secrets"
exit 0
