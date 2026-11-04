#!/bin/bash
set -e

NAMESPACE="sched-pin"
DEPLOYMENT="quote-engine"

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(echo "$JSON" | jq -c '.spec.template.spec')

TOL=$(jq '[.tolerations[]? | select(.key=="workload" and (.effect=="NoSchedule" or .effect==null) and ((.value=="latency" and (.operator // "Equal")=="Equal") or .operator=="Exists"))] | length' <<<"$SPEC")
if [[ "${TOL:-0}" -lt 1 ]]; then
    echo "❌ '$DEPLOYMENT' has no toleration for workload=latency:NoSchedule"
    exit 1
fi

# nodeSelector was ruled out: the question asks specifically for required node
# affinity, which is the mechanism being tested.
NODESEL=$(jq -r '.nodeSelector // {} | length' <<<"$SPEC")
if [[ "$NODESEL" -gt 0 ]]; then
    echo "❌ '$DEPLOYMENT' uses a nodeSelector; the question requires node affinity instead"
    exit 1
fi

REQ=$(jq -c '.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution // empty' <<<"$SPEC")
if [[ -z "$REQ" || "$REQ" == "null" ]]; then
    echo "❌ '$DEPLOYMENT' has no requiredDuringSchedulingIgnoredDuringExecution node affinity"
    exit 1
fi

MATCH=$(jq '[.nodeSelectorTerms[]?.matchExpressions[]? | select(.key=="tier" and .operator=="In" and (.values | index("realtime")))] | length' <<<"$REQ")
if [[ "${MATCH:-0}" -lt 1 ]]; then
    echo "❌ The node affinity does not require tier=realtime"
    exit 1
fi

CONTAINER=$(jq -r '.containers[0].name' <<<"$SPEC")
IMAGE=$(jq -r '.containers[0].image' <<<"$SPEC")
if [[ "$CONTAINER" != "engine" ]]; then
    echo "❌ The container is named '$CONTAINER', expected 'engine'"
    exit 1
fi
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ The container runs '$IMAGE', expected 'nginx:1.27.4'"
    exit 1
fi

echo "✅ '$DEPLOYMENT' tolerates the taint and requires tier=realtime by node affinity"
exit 0
