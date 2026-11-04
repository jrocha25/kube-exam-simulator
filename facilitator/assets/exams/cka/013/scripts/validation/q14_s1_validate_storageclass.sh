#!/bin/bash
set -e

SC="vault-local"

JSON=$(kubectl get storageclass "$SC" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ StorageClass '$SC' not found"
    exit 1
fi

GOT=$(echo "$JSON" | jq -c '{provisioner, volumeBindingMode, reclaimPolicy}')
WANT='{"provisioner":"kubernetes.io/no-provisioner","volumeBindingMode":"WaitForFirstConsumer","reclaimPolicy":"Retain"}'
if [[ "$GOT" != "$WANT" ]]; then
    echo "❌ '$SC' is $GOT"
    echo "   expected $WANT"
    exit 1
fi

echo "✅ '$SC' has no provisioner, waits for a consumer and retains volumes"
exit 0
