#!/bin/bash
set -e

NAMESPACE="stor-vault"
PVC="vault-claim"

for _ in $(seq 1 6); do
    STATE=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.status.phase}/{.spec.volumeName}' 2>/dev/null || true)
    [[ "$STATE" == "Bound/vault-pv-01" ]] && break
    sleep 5
done
if [[ "$STATE" != "Bound/vault-pv-01" ]]; then
    echo "❌ '$PVC' is '${STATE:-missing}', expected Bound to vault-pv-01"
    exit 1
fi

echo "✅ '$PVC' is bound to vault-pv-01"
exit 0
