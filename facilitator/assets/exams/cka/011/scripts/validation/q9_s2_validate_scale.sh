#!/bin/bash
set -e

NAMESPACE="wl-baggage"
STS="belt"

if ! kubectl get statefulset "$STS" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ StatefulSet '$STS' not found in namespace '$NAMESPACE'"
    exit 1
fi

DESIRED=$(kubectl get statefulset "$STS" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
if [[ "$DESIRED" != "1" ]]; then
    echo "❌ '$STS' declares ${DESIRED:-0} replicas, expected 1"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get statefulset "$STS" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    [[ "${READY:-0}" == "1" ]] && break
    sleep 5
done
if [[ "${READY:-0}" != "1" ]]; then
    echo "❌ '$STS' has ${READY:-0} ready replicas, expected 1"
    exit 1
fi

echo "✅ '$STS' is scaled to 1 ready replica"
exit 0
