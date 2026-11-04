#!/bin/bash
set -e

if ! kubectl get clusterrole node-viewer &> /dev/null; then
    echo "❌ ClusterRole 'node-viewer' not found"
    exit 1
fi

if ! kubectl get clusterrolebinding oncall-node-view &> /dev/null; then
    echo "❌ ClusterRoleBinding 'oncall-node-view' not found"
    exit 1
fi

SPEC=$(kubectl get clusterrolebinding oncall-node-view -o json)

NAME=$(echo "$SPEC" | jq -r '.roleRef.name')
if [[ "$NAME" != "node-viewer" ]]; then
    echo "❌ 'oncall-node-view' references ClusterRole '$NAME', expected 'node-viewer'"
    exit 1
fi

SUBJECT=$(echo "$SPEC" | jq -r '[.subjects[]? | select(.kind=="ServiceAccount" and .name=="oncall" and .namespace=="rbac-ops")] | length')
if [[ "$SUBJECT" == "0" ]]; then
    echo "❌ 'oncall-node-view' does not bind the ServiceAccount 'rbac-ops/oncall'"
    exit 1
fi

echo "✅ 'oncall' holds ClusterRole/node-viewer across the whole cluster"
exit 0
