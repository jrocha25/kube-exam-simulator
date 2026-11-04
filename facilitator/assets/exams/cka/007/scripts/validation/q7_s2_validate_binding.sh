#!/bin/bash
set -e

NAMESPACE="rbac-probe"
SA="probe-agent"
BINDING="probe-agent-endpoints"
CLUSTERROLE="endpoint-prober"

if ! kubectl get serviceaccount "$SA" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ ServiceAccount '$SA' not found in namespace '$NAMESPACE'"
    exit 1
fi

if ! kubectl get clusterrolebinding "$BINDING" &> /dev/null; then
    echo "❌ ClusterRoleBinding '$BINDING' not found"
    exit 1
fi

KIND=$(kubectl get clusterrolebinding "$BINDING" -o jsonpath='{.roleRef.kind}')
NAME=$(kubectl get clusterrolebinding "$BINDING" -o jsonpath='{.roleRef.name}')
if [[ "$KIND" != "ClusterRole" || "$NAME" != "$CLUSTERROLE" ]]; then
    echo "❌ ClusterRoleBinding '$BINDING' references '$KIND/$NAME', expected 'ClusterRole/$CLUSTERROLE'"
    exit 1
fi

MATCH=$(kubectl get clusterrolebinding "$BINDING" -o json | jq --arg sa "$SA" --arg ns "$NAMESPACE" \
    '[.subjects[]? | select(.kind == "ServiceAccount" and .name == $sa and .namespace == $ns)] | length')
if [[ "$MATCH" == "0" ]]; then
    echo "❌ ClusterRoleBinding '$BINDING' does not name ServiceAccount '$SA' in namespace '$NAMESPACE'"
    exit 1
fi

echo "✅ ClusterRoleBinding '$BINDING' grants '$CLUSTERROLE' to ServiceAccount '$SA'"
exit 0
