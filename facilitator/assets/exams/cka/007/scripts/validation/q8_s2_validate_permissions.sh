#!/bin/bash
set -e

NAMESPACE="rbac-identity"

# Grade the identity the workload actually runs as, not the one the Role was
# written for: those are the same thing only once the Deployment is fixed.
# Pods of a superseded ReplicaSet are still listed while they terminate and
# still report the old account, so skip anything scheduled for deletion.
live_accounts() {
    kubectl get pods -n "$NAMESPACE" -l app=inventory-sync -o json 2>/dev/null \
        | jq -r '[.items[] | select(.metadata.deletionTimestamp == null) | .spec.serviceAccountName] | unique | join(",")'
}

for _ in $(seq 1 12); do
    POD_SA=$(live_accounts)
    [[ -n "$POD_SA" && "$POD_SA" != *,* && "$POD_SA" != "default" ]] && break
    sleep 5
done

if [[ -z "$POD_SA" ]]; then
    echo "❌ No Pod of 'inventory-sync' is running in '$NAMESPACE'"
    exit 1
fi
if [[ "$POD_SA" == *,* ]]; then
    echo "❌ The Pods run as more than one account ($POD_SA)"
    exit 1
fi
if [[ "$POD_SA" == "default" ]]; then
    echo "❌ The Pods still run as the 'default' ServiceAccount"
    exit 1
fi

USER="system:serviceaccount:$NAMESPACE:$POD_SA"

check() {
    local expected="$1" verb="$2" resource="$3" namespace="$4"
    local answer
    answer=$(kubectl auth can-i "$verb" "$resource" --as="$USER" -n "$namespace" 2>/dev/null || true)
    if [[ "$answer" != "$expected" ]]; then
        echo "❌ '$USER': '$verb $resource' in '$namespace' returned '${answer:-<none>}', expected '$expected'"
        exit 1
    fi
}

for verb in get list watch update; do
    check yes "$verb" configmaps "$NAMESPACE"
done

# The account reconciles configuration; it was never meant to reach anything else.
check no delete configmaps "$NAMESPACE"
check no get    secrets    "$NAMESPACE"
check no list   configmaps default

echo "✅ The account the Pods run as ('$POD_SA') can reconcile ConfigMaps in '$NAMESPACE' and nothing beyond"
exit 0
