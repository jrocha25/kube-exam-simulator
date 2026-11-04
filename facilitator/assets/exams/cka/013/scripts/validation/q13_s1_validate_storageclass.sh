#!/bin/bash
set -e

SC="harbor-grow"

JSON=$(kubectl get storageclass "$SC" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ StorageClass '$SC' not found"
    exit 1
fi

GOT=$(echo "$JSON" | jq -c '{allowVolumeExpansion, provisioner, volumeBindingMode, reclaimPolicy}')
WANT='{"allowVolumeExpansion":true,"provisioner":"rancher.io/local-path","volumeBindingMode":"WaitForFirstConsumer","reclaimPolicy":"Delete"}'
if [[ "$GOT" != "$WANT" ]]; then
    echo "❌ '$SC' is $GOT"
    echo "   expected $WANT"
    exit 1
fi

echo "✅ '$SC' allows expansion and is otherwise unchanged"
exit 0
