#!/bin/bash
set -e

NAMESPACE="rbac-identity"
DEPLOYMENT="inventory-sync"
SA="inventory-sync"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

TEMPLATE_SA=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.serviceAccountName}')
if [[ "$TEMPLATE_SA" != "$SA" ]]; then
    echo "❌ The pod template of '$DEPLOYMENT' runs as '${TEMPLATE_SA:-default}', expected '$SA'"
    exit 1
fi

# Pods left over from the previous ReplicaSet are still listed while they
# terminate, and they still report the old account — ignore anything already
# scheduled for deletion.
live_accounts() {
    kubectl get pods -n "$NAMESPACE" -l app=inventory-sync -o json 2>/dev/null \
        | jq -r '[.items[] | select(.metadata.deletionTimestamp == null) | .spec.serviceAccountName] | unique | join(",")'
}

for _ in $(seq 1 12); do
    ACCOUNTS=$(live_accounts)
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    [[ "$ACCOUNTS" == "$SA" && "$READY" == "2" ]] && break
    sleep 5
done

if [[ "$ACCOUNTS" != "$SA" ]]; then
    echo "❌ The live Pods of '$DEPLOYMENT' run as '${ACCOUNTS:-<none>}', expected only '$SA'"
    exit 1
fi

# An empty Pod list would leave ACCOUNTS empty too, so the replica count is what
# proves there were Pods to check in the first place.
if [[ "$READY" != "2" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has ${READY:-0} ready replicas, expected 2"
    exit 1
fi

echo "✅ Every Pod of '$DEPLOYMENT' now runs as ServiceAccount '$SA'"
exit 0
