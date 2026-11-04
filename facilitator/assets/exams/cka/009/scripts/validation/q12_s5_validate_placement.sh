#!/bin/bash

set -e

# A required anti-affinity on the hostname key with 3 replicas means one per node
# across the three schedulable nodes. If the rule were preferred, or its selector
# matched nothing, the replicas could pile up and this is what would notice.

NAMESPACE="kustom-sched"
DEPLOYMENT="freight-api"
REPLICAS="3"

if [[ -f /tmp/exam/insufficient-nodes ]]; then
    echo "❌ This cluster has fewer than 3 schedulable nodes, so placement cannot be graded"
    echo "   See the shared setup warnings in the exam logs."
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
if [[ "$READY" != "$REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' is not fully ready (${READY:-0}/${REPLICAS}), so its placement proves nothing yet"
    exit 1
fi

DISTINCT=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' \
    | grep -v '^$' | sort -u | wc -l)

if [[ "$DISTINCT" != "$REPLICAS" ]]; then
    echo "❌ The $REPLICAS replicas occupy only ${DISTINCT} distinct node(s)"
    exit 1
fi

echo "✅ The $REPLICAS replicas are on $DISTINCT distinct nodes"
exit 0
