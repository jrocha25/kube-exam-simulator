#!/bin/bash
set -e

NAMESPACE="node-buoy"
DEPLOYMENT="buoy-agent"
NODE03=$(grep '^node03=' /tmp/exam/nodes.env | cut -d= -f2)

# Pods on a node whose kubelet died keep reporting Running for minutes, so a
# Running Pod is only evidence once the node itself is Ready.
READY=$(kubectl get node "$NODE03" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [[ "$READY" != "True" ]]; then
    echo "❌ node03 is not Ready"
    exit 1
fi

for _ in $(seq 1 12); do
    COUNT=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -o json 2>/dev/null | jq --arg n "$NODE03" '[.items[]
        | select(.spec.nodeName == $n and .metadata.deletionTimestamp == null)
        | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length')
    [[ "$COUNT" == "2" ]] && break
    sleep 5
done
if [[ "$COUNT" != "2" ]]; then
    echo "❌ $DEPLOYMENT has ${COUNT:-0} ready Pods on node03, expected 2"
    exit 1
fi

echo "✅ $DEPLOYMENT has 2 ready replicas on node03"
exit 0
