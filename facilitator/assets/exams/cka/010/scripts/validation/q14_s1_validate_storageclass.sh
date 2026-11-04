#!/bin/bash
set -e

SC="bulk-retain"

JSON=$(kubectl get storageclass "$SC" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ StorageClass '$SC' not found"
    exit 1
fi

PROVISIONER=$(jq -r '.provisioner' <<<"$JSON")
RECLAIM=$(jq -r '.reclaimPolicy // "Delete"' <<<"$JSON")
BINDING=$(jq -r '.volumeBindingMode // "Immediate"' <<<"$JSON")
DEFAULT=$(jq -r '.metadata.annotations["storageclass.kubernetes.io/is-default-class"] // "false"' <<<"$JSON")

[[ "$PROVISIONER" == "rancher.io/local-path" ]] || { echo "❌ provisioner is '$PROVISIONER', expected rancher.io/local-path"; exit 1; }
[[ "$RECLAIM" == "Retain" ]]                    || { echo "❌ reclaimPolicy is '$RECLAIM', expected Retain"; exit 1; }
[[ "$BINDING" == "WaitForFirstConsumer" ]]      || { echo "❌ volumeBindingMode is '$BINDING', expected WaitForFirstConsumer"; exit 1; }
[[ "$DEFAULT" != "true" ]]                      || { echo "❌ '$SC' is marked as the default StorageClass"; exit 1; }

echo "✅ StorageClass '$SC' is configured as specified"
exit 0
