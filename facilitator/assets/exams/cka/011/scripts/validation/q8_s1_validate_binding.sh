#!/bin/bash
set -e

NAMESPACE="stor-cargo"
CLAIM="cargo-claim"
VOLUME="cargo-fast"

if ! kubectl get pvc "$CLAIM" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ PersistentVolumeClaim '$CLAIM' not found in namespace '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 12); do
    PHASE=$(kubectl get pvc "$CLAIM" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Bound" ]] && break
    sleep 5
done
if [[ "$PHASE" != "Bound" ]]; then
    echo "❌ Claim '$CLAIM' is ${PHASE:-unknown}, expected Bound"
    exit 1
fi

BOUND_TO=$(kubectl get pvc "$CLAIM" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
if [[ "$BOUND_TO" != "$VOLUME" ]]; then
    echo "❌ Claim '$CLAIM' is bound to '${BOUND_TO:-nothing}', expected '$VOLUME'"
    exit 1
fi

echo "✅ Claim '$CLAIM' is bound to the '$VOLUME' volume"
exit 0
