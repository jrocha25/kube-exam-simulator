#!/bin/bash
set -e

NAMESPACE="rbac-identity"

for object in "serviceaccount/inventory-sync" "role/inventory-sync-role" "rolebinding/inventory-sync-binding" "deployment/inventory-sync"; do
    if ! kubectl get "$object" -n "$NAMESPACE" &> /dev/null; then
        echo "❌ '$object' does not exist in namespace '$NAMESPACE'"
        exit 1
    fi
done

REPLICAS=$(kubectl get deployment inventory-sync -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$REPLICAS" != "2" ]]; then
    echo "❌ Deployment 'inventory-sync' declares $REPLICAS replicas, expected 2"
    exit 1
fi

# The namespace's default account must not have been granted anything.
ANSWER=$(kubectl auth can-i list configmaps --as="system:serviceaccount:$NAMESPACE:default" -n "$NAMESPACE" 2>/dev/null || true)
if [[ "$ANSWER" == "yes" ]]; then
    echo "❌ The 'default' ServiceAccount in '$NAMESPACE' was granted access; the fix belongs on the workload's own account"
    exit 1
fi

echo "✅ The original objects are intact and the 'default' account was not widened"
exit 0
