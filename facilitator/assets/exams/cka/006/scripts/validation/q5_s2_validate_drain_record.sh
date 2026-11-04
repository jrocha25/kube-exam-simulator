#!/bin/bash
set -e

NAMESPACE="node-maint"
DEPLOYMENT="shop-web"
RECORD="/tmp/exam/q5/drained.txt"
EXPECTED_REPLICAS=4

if [[ ! -s "$RECORD" ]]; then
    echo "❌ '$RECORD' is missing or empty"
    exit 1
fi

# Every recorded name must look like a shop-web pod. The pods themselves are gone
# by now -- that is the point of a drain -- so the names cannot be resolved against
# the API, only their shape checked.
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ ^shop-web-[a-z0-9]+-[a-z0-9]+$ ]]; then
        echo "❌ '$RECORD' contains '$line', which is not a shop-web Pod name"
        exit 1
    fi
done < "$RECORD"

COUNT=$(grep -c '[^[:space:]]' "$RECORD" || true)
if [[ "$COUNT" -lt 1 ]]; then
    echo "❌ '$RECORD' lists no Pod names"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "${READY:-0}" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' has ${READY:-0}/$EXPECTED_REPLICAS ready replicas"
    exit 1
fi

DS_READY=$(kubectl get daemonset log-shipper -n "$NAMESPACE" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
DS_WANTED=$(kubectl get daemonset log-shipper -n "$NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
if [[ "${DS_READY:-0}" != "${DS_WANTED:-0}" || "${DS_WANTED:-0}" -lt 1 ]]; then
    echo "❌ DaemonSet 'log-shipper' has ${DS_READY:-0}/${DS_WANTED:-0} pods ready"
    exit 1
fi

echo "✅ $COUNT drained Pod names recorded, and both workloads are fully available"
exit 0
