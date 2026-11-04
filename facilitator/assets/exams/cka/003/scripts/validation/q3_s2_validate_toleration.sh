#!/bin/bash
set -e

NAMESPACE="node-agents"
DS_NAME="log-agent"

if ! kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ DaemonSet '$DS_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

MATCHES=$(kubectl get daemonset "$DS_NAME" -n "$NAMESPACE" -o json | jq '[.spec.template.spec.tolerations // [] | .[] | select(.operator == "Exists" and (has("key") | not) and (has("effect") | not))] | length')
if [[ "$MATCHES" == "0" ]]; then
    echo "❌ DaemonSet '$DS_NAME' has no toleration with operator 'Exists' and no key and no effect"
    exit 1
fi

echo "✅ DaemonSet '$DS_NAME' tolerates every taint"
exit 0
