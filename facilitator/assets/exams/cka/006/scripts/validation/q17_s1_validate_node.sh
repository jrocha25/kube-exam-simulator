#!/bin/bash
set -e

NODE=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$NODE" ]]; then
    echo "❌ No node is labelled ck-x.io/alias=node02"
    exit 1
fi

JSON=$(kubectl get node "$NODE" -o json)

TAINT=$(echo "$JSON" | jq -r '[.spec.taints[]? | select(.key=="workload")] | first // empty')
if [[ -z "$TAINT" ]]; then
    echo "❌ Node '$NODE' carries no taint with the key 'workload'"
    exit 1
fi

VALUE=$(jq -r '.value // empty' <<<"$TAINT")
EFFECT=$(jq -r '.effect // empty' <<<"$TAINT")
if [[ "$VALUE" != "latency" ]]; then
    echo "❌ The 'workload' taint has value '${VALUE:-<none>}', expected 'latency'"
    exit 1
fi
if [[ "$EFFECT" != "NoSchedule" ]]; then
    echo "❌ The 'workload' taint has effect '$EFFECT', expected 'NoSchedule'"
    exit 1
fi

TIER=$(echo "$JSON" | jq -r '.metadata.labels.tier // empty')
if [[ "$TIER" != "realtime" ]]; then
    echo "❌ Node '$NODE' carries tier='${TIER:-<none>}', expected 'realtime'"
    exit 1
fi

echo "✅ Node '$NODE' carries the workload=latency:NoSchedule taint and tier=realtime"
exit 0
