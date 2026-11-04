#!/bin/bash
set -e

NAMESPACE="sched-pin"
DEPLOYMENT="quote-engine"
EXPECTED_REPLICAS=2

NODE=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$NODE" ]]; then
    echo "❌ No node is labelled ck-x.io/alias=node02"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "${READY:-0}" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' has ${READY:-0}/$EXPECTED_REPLICAS ready replicas"
    exit 1
fi

NODES=$(kubectl get pods -n "$NAMESPACE" -l app=quote-engine -o json \
    | jq -r '[.items[] | select(.status.phase=="Running") | .spec.nodeName] | unique | join(",")')
if [[ "$NODES" != "$NODE" ]]; then
    echo "❌ Running replicas are on '${NODES:-nowhere}', expected all of them on '$NODE'"
    exit 1
fi

echo "✅ Both '$DEPLOYMENT' replicas are Running on '$NODE'"
exit 0
