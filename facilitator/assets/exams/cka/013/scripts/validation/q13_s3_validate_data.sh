#!/bin/bash
set -e

NAMESPACE="stor-ledger"
STATE_FILE=/tmp/exam/q13/data.sha256

# A constraint: true of an untouched claim, so it only counts after the resize.
if [[ "$(kubectl get pvc ledger-data -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)" != "1Gi" ]]; then
    echo "❌ ledger-data has not been grown yet"
    exit 1
fi

if [[ "$(kubectl get pod ledger-writer -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)" != "Running" ]]; then
    echo "❌ ledger-writer is not running"
    exit 1
fi

SUM=$(kubectl exec -n "$NAMESPACE" ledger-writer -- cat /data/ledger.txt 2>/dev/null | sha256sum | awk '{print $1}')
if [[ "$SUM" != "$(cat "$STATE_FILE" 2>/dev/null)" ]]; then
    echo "❌ The ledger data changed or is gone"
    exit 1
fi

echo "✅ ledger-writer still runs with its data intact"
exit 0
