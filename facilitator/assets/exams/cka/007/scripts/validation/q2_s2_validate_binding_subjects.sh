#!/bin/bash
set -e

BINDING="infra-auditors"
CLUSTERROLE="infra-auditor"

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

SUBJECTS=$(kubectl get clusterrolebinding "$BINDING" -o json)

GROUP=$(echo "$SUBJECTS" | jq '[.subjects[]? | select(.kind == "Group" and .name == "platform-auditors")] | length')
if [[ "$GROUP" == "0" ]]; then
    echo "❌ ClusterRoleBinding '$BINDING' has no Group subject named 'platform-auditors'"
    exit 1
fi

USER=$(echo "$SUBJECTS" | jq '[.subjects[]? | select(.kind == "User" and .name == "dana")] | length')
if [[ "$USER" == "0" ]]; then
    echo "❌ ClusterRoleBinding '$BINDING' has no User subject named 'dana'"
    exit 1
fi

echo "✅ ClusterRoleBinding '$BINDING' grants '$CLUSTERROLE' to the group 'platform-auditors' and the user 'dana'"
exit 0
