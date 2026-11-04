#!/bin/bash
set -e

NAMESPACE="manifest-ops"
DEPLOYMENT="manifest-api"

READY=""
UPDATED=""
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    UPDATED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null || true)
    [[ "$READY" == "2" && "$UPDATED" == "2" ]] && break
    sleep 5
done
if [[ "$READY" != "2" || "$UPDATED" != "2" ]]; then
    echo "❌ '$DEPLOYMENT' has not rolled out 2 ready replicas (ready '${READY:-0}', updated '${UPDATED:-0}')"
    exit 1
fi

PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -o json \
    | jq -r '.items[] | select(.metadata.deletionTimestamp == null)
             | select(any(.spec.initContainers[]?; .name == "manifest-shipper")) | .metadata.name')
if [[ -z "$PODS" ]]; then
    echo "❌ No running Pod of '$DEPLOYMENT' carries the manifest-shipper sidecar"
    exit 1
fi

for pod in $PODS; do
    LOGS=$(kubectl logs -n "$NAMESPACE" "$pod" -c manifest-shipper 2>/dev/null || true)
    if ! echo "$LOGS" | grep -q 'migrate step 1'; then
        echo "❌ The sidecar in '$pod' did not ship schema-migrate's output"
        exit 1
    fi
    if ! echo "$LOGS" | grep -q 'api heartbeat'; then
        echo "❌ The sidecar in '$pod' did not ship the api container's output"
        exit 1
    fi
done

echo "✅ Every Pod's sidecar shipped both schema-migrate's and api's log lines"
exit 0
