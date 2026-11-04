#!/bin/bash
set -e

NAMESPACE="sched-priority"
DEPLOYMENT="bulk-import"

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found -- it was not to be deleted"
    exit 1
fi

PC=$(echo "$JSON" | jq -r '.spec.template.spec.priorityClassName // empty')
if [[ "$PC" != "batch-low" ]]; then
    echo "❌ '$DEPLOYMENT' uses priorityClassName '${PC:-<none>}', expected 'batch-low'"
    exit 1
fi

REPLICAS=$(echo "$JSON" | jq -r '.spec.replicas')
if [[ "$REPLICAS" != "3" ]]; then
    echo "❌ '$DEPLOYMENT' declares $REPLICAS replicas, expected the original 3."
    echo "   It was not to be scaled by hand -- preemption does the work."
    exit 1
fi

PIN=$(echo "$JSON" | jq -r '.spec.template.spec.nodeSelector["ck-x.io/alias"] // empty')
if [[ "$PIN" != "node03" ]]; then
    echo "❌ '$DEPLOYMENT' is no longer pinned to node03 (nodeSelector: ${PIN:-<none>})"
    exit 1
fi

echo "✅ '$DEPLOYMENT' carries the low priority class and was not scaled or unpinned"
exit 0
