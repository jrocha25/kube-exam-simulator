#!/bin/bash
set -e

NAMESPACE="ledger"
DEPLOYMENT="ledger-db"
DATA_FILE=/srv/ck-x/ledger/ledger.token

READY=""
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    [[ "$READY" == "1" ]] && break
    [[ -z "$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o name 2>/dev/null)" ]] && break
    sleep 5
done
if [[ "$READY" != "1" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' in '$NAMESPACE' does not have 1 ready replica"
    exit 1
fi

CLAIM=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}')
if [[ "$CLAIM" != "ledger-data" ]]; then
    echo "❌ '$DEPLOYMENT' mounts the claim '$CLAIM', not ledger-data"
    exit 1
fi

# The ledger record lives on node01's disk; reading it from the running Pod
# proves the data on the retained volume is the data the database sees.
EXPECTED=$(ssh -o ConnectTimeout=10 -o BatchMode=yes node01 "cat $DATA_FILE" 2>/dev/null </dev/null || cat /tmp/exam/.q5/token 2>/dev/null || true)
POD=$(kubectl get pods -n "$NAMESPACE" -l app=ledger-db --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
ACTUAL=$(kubectl exec -n "$NAMESPACE" "$POD" -- cat /var/lib/ledger/ledger.token 2>/dev/null || true)
if [[ -z "$EXPECTED" || "$ACTUAL" != "$EXPECTED" ]]; then
    echo "❌ Pod '$POD' does not see the original ledger record at /var/lib/ledger/ledger.token"
    exit 1
fi

echo "✅ '$DEPLOYMENT' is running on the retained volume and reads the original ledger record"
exit 0
