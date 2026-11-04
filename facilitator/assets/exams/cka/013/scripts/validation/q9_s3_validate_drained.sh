#!/bin/bash
set -e

NODE02=$(grep '^node02=' /tmp/exam/nodes.env | cut -d= -f2)

if [[ "$(kubectl get node "$NODE02" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)" != "true" ]]; then
    echo "❌ node02 is not cordoned"
    exit 1
fi

for _ in $(seq 1 6); do
    LEFT=$(kubectl get pods -A --field-selector "spec.nodeName=${NODE02}" -o json | jq -r '[.items[]
        | select(.metadata.deletionTimestamp == null)
        | select(all(.metadata.ownerReferences[]?; .kind != "DaemonSet"))
        | "\(.metadata.namespace)/\(.metadata.name)"] | join(" ")')
    [[ -z "$LEFT" ]] && break
    sleep 5
done
if [[ -n "$LEFT" ]]; then
    echo "❌ node02 still runs non-DaemonSet Pods: $LEFT"
    exit 1
fi

echo "✅ node02 is cordoned and drained"
exit 0
