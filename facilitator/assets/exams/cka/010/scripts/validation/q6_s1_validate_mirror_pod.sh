#!/bin/bash
set -e

NAMESPACE="static-edge"
POD_BASE="edge-cache"
CONTAINER="cache"
IMAGE="nginx:1.27.4"

NODE=$(kubectl get nodes -l ck-x.io/alias=node01 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$NODE" ]]; then
    echo "❌ No node is labelled ck-x.io/alias=node01"
    exit 1
fi

# The kubelet names a static Pod's mirror <name>-<nodeName>, and marks it with
# an ownerReference to the Node. A Pod created through the API server has
# neither, whatever it is called.
POD="${POD_BASE}-${NODE}"
for _ in $(seq 1 12); do
    JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
    [[ -n "$JSON" && "$(jq -r '.status.phase' <<<"$JSON")" == "Running" ]] && break
    sleep 5
done
if [[ -z "$JSON" ]]; then
    echo "❌ No mirror Pod '$POD' in namespace '$NAMESPACE' -- is the manifest on node01, in the right namespace?"
    exit 1
fi

OWNER=$(jq -r '.metadata.ownerReferences[0].kind // empty' <<<"$JSON")
if [[ "$OWNER" != "Node" ]]; then
    echo "❌ '$POD' is not a static Pod (it is not owned by the Node)"
    exit 1
fi

PHASE=$(jq -r '.status.phase' <<<"$JSON")
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ '$POD' is $PHASE, expected Running"
    exit 1
fi

COUNT=$(jq '.spec.containers | length' <<<"$JSON")
NAME=$(jq -r '.spec.containers[0].name' <<<"$JSON")
IMG=$(jq -r '.spec.containers[0].image' <<<"$JSON")
if [[ "$COUNT" != "1" || "$NAME" != "$CONTAINER" || "$IMG" != "$IMAGE" ]]; then
    echo "❌ '$POD' must have exactly one container named '$CONTAINER' running '$IMAGE' (found $COUNT container(s), '$NAME' running '$IMG')"
    exit 1
fi

echo "✅ Static Pod '$POD' is Running on node01 with container '$CONTAINER' ($IMAGE)"
exit 0
