#!/bin/bash
set -e

NAMESPACE="wl-baggage"
STS="belt"

if ! kubectl get statefulset "$STS" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ StatefulSet '$STS' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get statefulset "$STS" -n "$NAMESPACE" -o json)

WHEN_SCALED=$(jq -r '.spec.persistentVolumeClaimRetentionPolicy.whenScaled // "<unset>"' <<<"$JSON")
WHEN_DELETED=$(jq -r '.spec.persistentVolumeClaimRetentionPolicy.whenDeleted // "<unset>"' <<<"$JSON")

if [[ "$WHEN_SCALED" != "Delete" ]]; then
    echo "❌ '$STS' reclaims claims on scale-in as '${WHEN_SCALED}', expected 'Delete'"
    exit 1
fi
if [[ "$WHEN_DELETED" != "Retain" ]]; then
    echo "❌ '$STS' reclaims claims on delete as '${WHEN_DELETED}', expected 'Retain'"
    exit 1
fi

echo "✅ '$STS' deletes per-Pod claims on scale-in and keeps them on delete"
exit 0
