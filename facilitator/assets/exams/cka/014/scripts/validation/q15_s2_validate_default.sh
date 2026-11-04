#!/bin/bash
set -e

DEFAULTS=$(kubectl get storageclass -o json | jq -r '.items[]
    | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true")
    | .metadata.name')

if [[ "$DEFAULTS" != "harbor-fast" ]]; then
    echo "❌ The default StorageClass must be harbor-fast and only harbor-fast; defaults are: '$(echo $DEFAULTS)'"
    exit 1
fi

if ! kubectl get storageclass standard >/dev/null 2>&1; then
    echo "❌ The StorageClass 'standard' was deleted; it must remain, just not as the default"
    exit 1
fi

echo "✅ harbor-fast is the only default StorageClass and standard still exists"
exit 0
