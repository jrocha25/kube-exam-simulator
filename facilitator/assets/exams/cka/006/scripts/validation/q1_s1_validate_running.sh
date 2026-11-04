#!/bin/bash
set -e

NAMESPACE="ops-probe"
POD_LABEL="app=node-probe"

# A static Pod's mirror object is named <pod>-<node>, and the node name depends on
# the cluster, so select on the label instead of guessing the name.
POD=$(kubectl get pods -n "$NAMESPACE" -l "$POD_LABEL" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
    echo "❌ No Pod labelled '$POD_LABEL' found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json)

PHASE=$(echo "$JSON" | jq -r '.status.phase')
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is '$PHASE', expected 'Running'"
    exit 1
fi

READY=$(echo "$JSON" | jq -r '.status.containerStatuses[0].ready')
if [[ "$READY" != "true" ]]; then
    echo "❌ Pod '$POD' is Running but its container is not ready"
    exit 1
fi

# Still a static Pod: the kubelet stamps mirror pods with this annotation, and an
# ordinary Pod created through the API server does not carry it.
MIRROR=$(echo "$JSON" | jq -r '.metadata.annotations["kubernetes.io/config.mirror"] // empty')
if [[ -z "$MIRROR" ]]; then
    echo "❌ Pod '$POD' is not a static Pod -- it was created through the API server"
    exit 1
fi

NODE=$(echo "$JSON" | jq -r '.spec.nodeName')
ALIAS=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.ck-x\.io/alias}' 2>/dev/null || true)
if [[ "$ALIAS" != "node01" ]]; then
    echo "❌ Pod '$POD' runs on '$NODE' (${ALIAS:-no alias}), expected node01"
    exit 1
fi

CONTAINERS=$(echo "$JSON" | jq -r '[.spec.containers[].name] | join(",")')
if [[ "$CONTAINERS" != "probe" ]]; then
    echo "❌ Pod '$POD' has containers '$CONTAINERS', expected exactly one named 'probe'"
    exit 1
fi

echo "✅ Static Pod '$POD' is Running on node01"
exit 0
