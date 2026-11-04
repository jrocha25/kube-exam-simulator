#!/bin/bash
set -e

NAMESPACE="api-beacon"
POD="beacon-probe"
SA="beacon-reader"

if ! kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json)

GOT_SA=$(jq -r '.spec.serviceAccountName // "default"' <<<"$JSON")
if [[ "$GOT_SA" != "$SA" ]]; then
    echo "❌ Pod '$POD' runs as ServiceAccount '${GOT_SA}', expected '${SA}'"
    exit 1
fi

IMAGE=$(jq -r '.spec.containers[0].image // ""' <<<"$JSON")
if [[ "$IMAGE" != curlimages/curl:* ]]; then
    echo "❌ Pod '$POD' runs image '${IMAGE:-none}', expected a curlimages/curl image"
    exit 1
fi

for _ in $(seq 1 8); do
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
done
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is ${PHASE:-absent}, expected Running"
    exit 1
fi

echo "✅ Pod '$POD' is running under the '$SA' ServiceAccount"
exit 0
