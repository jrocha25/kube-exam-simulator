#!/bin/bash
set -e

NAMESPACE="priority"
DEPLOYMENT="edge-proxy"
PRIORITY_CLASS="edge-critical"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

CURRENT=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.priorityClassName}')
if [[ "$CURRENT" != "$PRIORITY_CLASS" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' must use the PriorityClass '$PRIORITY_CLASS' (got: '${CURRENT:-<none>}')"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' uses the PriorityClass '$PRIORITY_CLASS'"
exit 0
