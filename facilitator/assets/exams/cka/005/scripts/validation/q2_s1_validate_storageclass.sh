#!/bin/bash
set -e

SC="slow-retain"

if ! kubectl get storageclass "$SC" &> /dev/null; then
    echo "❌ StorageClass '$SC' not found"
    exit 1
fi

PROVISIONER=$(kubectl get storageclass "$SC" -o jsonpath='{.provisioner}')
if [[ "$PROVISIONER" != "rancher.io/local-path" ]]; then
    echo "❌ Incorrect provisioner. Expected 'rancher.io/local-path', got '$PROVISIONER'"
    exit 1
fi

RECLAIM=$(kubectl get storageclass "$SC" -o jsonpath='{.reclaimPolicy}')
if [[ "$RECLAIM" != "Retain" ]]; then
    echo "❌ Incorrect reclaim policy. Expected 'Retain', got '$RECLAIM'"
    exit 1
fi

BINDING=$(kubectl get storageclass "$SC" -o jsonpath='{.volumeBindingMode}')
if [[ "$BINDING" != "WaitForFirstConsumer" ]]; then
    echo "❌ Incorrect volume binding mode. Expected 'WaitForFirstConsumer', got '$BINDING'"
    exit 1
fi

EXPANSION=$(kubectl get storageclass "$SC" -o jsonpath='{.allowVolumeExpansion}')
if [[ "$EXPANSION" != "true" ]]; then
    echo "❌ '$SC' does not allow volume expansion"
    exit 1
fi

echo "✅ StorageClass '$SC' is configured correctly"
exit 0
