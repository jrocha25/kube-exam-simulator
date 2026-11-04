#!/bin/bash
set -e

SC="harbor-fast"

JSON=$(kubectl get storageclass "$SC" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ StorageClass '$SC' not found"
    exit 1
fi

if ! echo "$JSON" | jq -e '.provisioner == "rancher.io/local-path"
        and .volumeBindingMode == "WaitForFirstConsumer"
        and .reclaimPolicy == "Retain"
        and .allowVolumeExpansion == true' >/dev/null; then
    echo "❌ '$SC' must use rancher.io/local-path, WaitForFirstConsumer, Retain and allow expansion: $(echo "$JSON" | jq -c '{provisioner, volumeBindingMode, reclaimPolicy, allowVolumeExpansion}')"
    exit 1
fi

echo "✅ StorageClass '$SC' is configured as required"
exit 0
