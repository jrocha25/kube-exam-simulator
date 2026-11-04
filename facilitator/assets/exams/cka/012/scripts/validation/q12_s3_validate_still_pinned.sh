#!/bin/bash
set -e

# A constraint check, guarded on the Pod running: letting the Pod go anywhere
# else would get it scheduled without tolerating anything, which is not the
# lesson. Either form of pinning is accepted -- the question says "stay pinned to
# node03", not how.

NAMESPACE="sched-borehole"
POD="borehole-sampler"
ALIAS="node03"

NODE=$(awk -F= -v a="$ALIAS" '$1==a {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1)
if [[ -z "$NODE" ]]; then
    NODE=$(kubectl get nodes -l "ck-x.io/alias=${ALIAS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi
if [[ "$(jq -r '.status.phase // ""' <<<"$JSON")" != "Running" ]]; then
    echo "❌ '$POD' is not Running yet, so there is nothing to confirm"
    exit 1
fi

SELECTOR_ALIAS=$(jq -r '.spec.nodeSelector["ck-x.io/alias"] // ""' <<<"$JSON")
NODE_NAME=$(jq -r '.spec.nodeName // ""' <<<"$JSON")
AFFINITY=$(jq -r '[.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?.matchExpressions[]?.values[]?] | join(",")' <<<"$JSON")

if [[ "$SELECTOR_ALIAS" == "$ALIAS" ]]; then
    echo "✅ '$POD' is still pinned to ${ALIAS} by nodeSelector"
    exit 0
fi
if [[ -n "$NODE" && ( "$NODE_NAME" == "$NODE" || "$AFFINITY" == *"$NODE"* || "$AFFINITY" == *"$ALIAS"* ) ]]; then
    echo "✅ '$POD' is still pinned to ${ALIAS}"
    exit 0
fi

echo "❌ '$POD' is no longer pinned to ${ALIAS}"
echo "   nodeSelector ck-x.io/alias='${SELECTOR_ALIAS:-unset}', nodeName '${NODE_NAME:-unset}'"
exit 1
