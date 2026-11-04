#!/bin/bash
set -e

NAMESPACE="ds-fleet"
DS="node-collector"

if ! kubectl get daemonset "$DS" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ DaemonSet '$DS' not found in namespace '$NAMESPACE'"
    exit 1
fi

# Graded per node, never as a count: node02 and node03 belong to other
# questions and may be NotReady or absent when this runs.
for alias in controlplane node01; do
    NODE=$(kubectl get nodes -l "ck-x.io/alias=${alias}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -z "$NODE" ]]; then
        echo "❌ No node is labelled ck-x.io/alias=${alias}"
        exit 1
    fi
    for _ in $(seq 1 12); do
        READY=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=${NODE},status.phase=Running" -o json 2>/dev/null \
            | jq --arg ds "$DS" '[.items[] | select(.metadata.ownerReferences[]? | .kind=="DaemonSet" and .name==$ds) | select(.status.containerStatuses[0].ready == true)] | length')
        [[ "${READY:-0}" -ge 1 ]] && break
        sleep 5
    done
    if [[ "${READY:-0}" -lt 1 ]]; then
        echo "❌ No Running '$DS' Pod on ${alias} ('$NODE')"
        exit 1
    fi
done

echo "✅ '$DS' Pods are Running on the control plane and on node01"
exit 0
