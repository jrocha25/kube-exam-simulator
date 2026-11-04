#!/bin/bash
set -e

# storageClassName has to be the empty string, not simply absent: kind ships a
# default StorageClass, and admission fills an omitted field in with it, which
# would provision a new volume instead of binding to either of the two staged
# ones.
#
# The "do not name the volume directly" constraint is checked through the
# selector rather than through spec.volumeName -- the binding controller writes
# volumeName onto every bound claim, so an empty one is not evidence of anything.

NAMESPACE="stor-cargo"
CLAIM="cargo-claim"

if ! kubectl get pvc "$CLAIM" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ PersistentVolumeClaim '$CLAIM' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get pvc "$CLAIM" -n "$NAMESPACE" -o json)

SC=$(jq -r '.spec.storageClassName // "<unset>"' <<<"$JSON")
if [[ "$SC" != "" ]]; then
    echo "❌ Claim '$CLAIM' uses storageClassName '${SC}', expected no StorageClass at all"
    exit 1
fi

REQ=$(jq -r '.spec.resources.requests.storage // ""' <<<"$JSON")
if [[ "$REQ" != "2Gi" ]]; then
    echo "❌ Claim '$CLAIM' requests '${REQ:-nothing}', expected '2Gi'"
    exit 1
fi

if ! jq -e '(.spec.accessModes // []) == ["ReadWriteOnce"]' <<<"$JSON" >/dev/null; then
    MODES=$(jq -r '(.spec.accessModes // []) | join(", ")' <<<"$JSON")
    echo "❌ Claim '$CLAIM' has access modes '${MODES:-none}', expected only 'ReadWriteOnce'"
    exit 1
fi

if ! jq -e '(.spec.selector // {}) | length > 0' <<<"$JSON" >/dev/null; then
    echo "❌ Claim '$CLAIM' has no label selector, so nothing makes it choose 'cargo-fast' over 'cargo-slow'"
    exit 1
fi

echo "✅ Claim '$CLAIM' requests 2Gi ReadWriteOnce with no StorageClass and selects on labels"
exit 0
