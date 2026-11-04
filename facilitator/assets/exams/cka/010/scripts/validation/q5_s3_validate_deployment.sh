#!/bin/bash
set -e

NAMESPACE="node-outage"
DEPLOYMENT="sensor-relay"
EXPECTED_REPLICAS=2

NODE=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$NODE" ]]; then
    echo "❌ No node is labelled ck-x.io/alias=node02"
    exit 1
fi

# A Pod on a node whose kubelet is down keeps reporting Running for the five
# minutes it takes the node controller to evict it, so "Running on node02" is
# only evidence once node02 itself is Ready.
READY=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [[ "$READY" != "True" ]]; then
    echo "❌ node02 ('$NODE') is not Ready, so nothing on it is really running"
    exit 1
fi

DEPLOY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$DEPLOY" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

REPLICAS=$(jq -r '.spec.replicas' <<<"$DEPLOY")
SELECTOR=$(jq -r '.spec.template.spec.nodeSelector["ck-x.io/alias"] // empty' <<<"$DEPLOY")
if [[ "$REPLICAS" != "$EXPECTED_REPLICAS" || "$SELECTOR" != "node02" ]]; then
    echo "❌ '$DEPLOYMENT' was modified: replicas=$REPLICAS, nodeSelector=${SELECTOR:-none} (expected 2 replicas pinned to node02)"
    exit 1
fi

# Once the node is back the evicted replicas need a moment to be rescheduled.
for _ in $(seq 1 12); do
    RUNNING=$(kubectl get pods -n "$NAMESPACE" -l "app=$DEPLOYMENT" \
        --field-selector "spec.nodeName=${NODE},status.phase=Running" -o json 2>/dev/null \
        | jq '[.items[] | select(.status.containerStatuses[0].ready == true)] | length')
    [[ "${RUNNING:-0}" -ge "$EXPECTED_REPLICAS" ]] && break
    sleep 5
done

if [[ "${RUNNING:-0}" -lt "$EXPECTED_REPLICAS" ]]; then
    echo "❌ ${RUNNING:-0}/$EXPECTED_REPLICAS '$DEPLOYMENT' replicas are Running on node02"
    exit 1
fi

echo "✅ Both '$DEPLOYMENT' replicas are Running on node02"
exit 0
