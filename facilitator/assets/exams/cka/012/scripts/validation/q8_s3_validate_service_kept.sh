#!/bin/bash
set -e

# A constraint check: the per-Pod record only exists because the Service is
# headless, so turning it into a ClusterIP Service to make something else work
# would quietly destroy what the question is about. Guarded on the lookup having
# been captured, so it is not a free mark.

NAMESPACE="dns-station"
SERVICE="station-index"
STATEFULSET="station-index"
FILE="/tmp/exam/q8/lookup.txt"
POD="station-index-0"
WANT_REPLICAS=2

POD_IP=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$POD_IP" ]] || [[ ! -s "$FILE" ]] || ! grep -qF -- "$POD_IP" "$FILE"; then
    echo "❌ The lookup has not been captured yet, so there is nothing to confirm"
    exit 1
fi

CLUSTER_IP=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ "$CLUSTER_IP" != "None" ]]; then
    echo "❌ Service '$SERVICE' has clusterIP '${CLUSTER_IP:-absent}'; it was a headless Service and had to stay one"
    exit 1
fi

REPLICAS=$(kubectl get statefulset "$STATEFULSET" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
if [[ "$REPLICAS" != "$WANT_REPLICAS" ]]; then
    echo "❌ StatefulSet '$STATEFULSET' declares '${REPLICAS:-none}' replicas, and it was to stay ${WANT_REPLICAS}"
    exit 1
fi

echo "✅ '$SERVICE' is still headless and '$STATEFULSET' still has ${WANT_REPLICAS} replicas"
exit 0
