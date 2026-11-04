#!/bin/bash
set -e

NAMESPACE="store-tier"
PVC="archive-claim"

if ! kubectl get pvc "$PVC" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ PersistentVolumeClaim '$PVC' not found in namespace '$NAMESPACE'"
    exit 1
fi

CLASS=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.spec.storageClassName}')
if [[ "$CLASS" != "slow-retain" ]]; then
    echo "❌ '$PVC' uses storage class '${CLASS:-<none>}', expected 'slow-retain'"
    exit 1
fi

MODES=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.spec.accessModes[*]}')
if [[ "$MODES" != "ReadWriteOnce" ]]; then
    echo "❌ Incorrect access modes on '$PVC'. Expected 'ReadWriteOnce', got '$MODES'"
    exit 1
fi

REQUEST=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}')
if [[ "$REQUEST" != "2Gi" ]]; then
    echo "❌ Incorrect storage request on '$PVC'. Expected '2Gi', got '$REQUEST'"
    exit 1
fi

PHASE=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [[ "$PHASE" != "Bound" ]]; then
    echo "❌ '$PVC' is '$PHASE', expected 'Bound'"
    exit 1
fi

echo "✅ '$PVC' requests 2Gi ReadWriteOnce from 'slow-retain' and is Bound"
exit 0
