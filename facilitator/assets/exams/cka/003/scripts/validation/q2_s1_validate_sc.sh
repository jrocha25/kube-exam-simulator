#!/bin/bash
set -e

SC_NAME="retain-local"

if ! kubectl get storageclass "$SC_NAME" &> /dev/null; then
    echo "❌ StorageClass '$SC_NAME' not found"
    exit 1
fi

PROVISIONER=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.provisioner}')
if [[ "$PROVISIONER" != "rancher.io/local-path" ]]; then
    echo "❌ Incorrect provisioner. Expected 'rancher.io/local-path', got '$PROVISIONER'"
    exit 1
fi

RECLAIM=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.reclaimPolicy}')
if [[ "$RECLAIM" != "Retain" ]]; then
    echo "❌ Incorrect reclaim policy. Expected 'Retain', got '$RECLAIM'"
    exit 1
fi

BINDING=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.volumeBindingMode}')
if [[ "$BINDING" != "WaitForFirstConsumer" ]]; then
    echo "❌ Incorrect volume binding mode. Expected 'WaitForFirstConsumer', got '$BINDING'"
    exit 1
fi

EXPANSION=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.allowVolumeExpansion}')
if [[ "$EXPANSION" != "true" ]]; then
    echo "❌ Volume expansion is not allowed on '$SC_NAME' (got: '$EXPANSION')"
    exit 1
fi

IS_DEFAULT=$(kubectl get storageclass "$SC_NAME" -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')
if [[ "$IS_DEFAULT" == "true" ]]; then
    echo "❌ StorageClass '$SC_NAME' must not be marked as the default storage class"
    exit 1
fi

echo "✅ StorageClass '$SC_NAME' is configured correctly"
exit 0
