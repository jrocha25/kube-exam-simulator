#!/bin/bash
set -e

NAMESPACE="ds-deice"
DS="deice"

if ! kubectl get daemonset "$DS" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ DaemonSet '$DS' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get daemonset "$DS" -n "$NAMESPACE" -o json)

for pair in "app=deice" "zone=apron"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    GOT=$(jq -r --arg k "$key" '.spec.template.metadata.labels[$k] // ""' <<<"$JSON")
    if [[ "$GOT" != "$value" ]]; then
        echo "❌ The Pods carry ${key}='${GOT:-unset}', expected '${value}'"
        exit 1
    fi
done

echo "✅ The Pods carry app=deice and zone=apron"
exit 0
