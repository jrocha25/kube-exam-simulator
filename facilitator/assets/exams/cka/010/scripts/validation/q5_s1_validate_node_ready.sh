#!/bin/bash
set -e

NODE=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$NODE" ]]; then
    echo "❌ No node is labelled ck-x.io/alias=node02"
    exit 1
fi

# A kubelet that was just restarted needs a few seconds to report in.
for _ in $(seq 1 12); do
    READY=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$READY" == "True" ]] && break
    sleep 5
done

if [[ "$READY" != "True" ]]; then
    echo "❌ node02 ('$NODE') is not Ready"
    exit 1
fi

echo "✅ node02 ('$NODE') reports Ready"
exit 0
