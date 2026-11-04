#!/bin/bash
set -e

# "node03's configuration is untouched" is part of this step rather than a
# constraint check of its own. Removing the taint is the forbidden fix and it does
# get the Pod running, so if it were graded separately it would still collect half
# the question.

NAMESPACE="sched-borehole"
POD="borehole-sampler"
ALIAS="node03"
TAINT_KEY="seismo.io/borehole"
TAINT_VALUE="restricted"

NODE=$(awk -F= -v a="$ALIAS" '$1==a {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1)
if [[ -z "$NODE" ]]; then
    NODE=$(kubectl get nodes -l "ck-x.io/alias=${ALIAS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [[ -z "$NODE" ]]; then
    echo "❌ No node carries the label ck-x.io/alias=${ALIAS}"
    exit 1
fi
if [[ "$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" != "True" ]]; then
    echo "❌ Node '${NODE}' (${ALIAS}) is not Ready, so what runs on it cannot be judged"
    exit 1
fi

if ! kubectl get node "$NODE" -o json 2>/dev/null | jq -e --arg k "$TAINT_KEY" --arg v "$TAINT_VALUE" '
    [(.spec.taints // [])[] | select(.key == $k and .value == $v and .effect == "NoSchedule")] | length == 1' >/dev/null; then
    CURRENT=$(kubectl get node "$NODE" -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect} {end}' 2>/dev/null || true)
    echo "❌ Node '${NODE}' (${ALIAS}) no longer carries ${TAINT_KEY}=${TAINT_VALUE}:NoSchedule"
    echo "   Its taints are now: ${CURRENT:-none}"
    echo "   The node belongs to the platform team; the Pod had to be made acceptable to it instead."
    exit 1
fi

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 8); do
    PHASE=$(jq -r '.status.phase // ""' <<<"$JSON")
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
    JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
done

PHASE=$(jq -r '.status.phase // ""' <<<"$JSON")
ON=$(jq -r '.spec.nodeName // ""' <<<"$JSON")

if [[ "$PHASE" != "Running" ]]; then
    echo "❌ '$POD' is ${PHASE:-absent}, expected Running"
    if [[ "$PHASE" == "Pending" ]]; then
        echo "   kubectl describe node ${NODE} says what the node will not accept."
    fi
    exit 1
fi
if [[ "$ON" != "$NODE" ]]; then
    echo "❌ '$POD' runs on '${ON:-nowhere}', not on '${NODE}' (${ALIAS})"
    exit 1
fi

echo "✅ '$POD' is Running on ${ALIAS}, which still carries its own taint"
exit 0
