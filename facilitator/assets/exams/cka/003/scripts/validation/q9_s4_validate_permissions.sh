#!/bin/bash
set -e

SA="system:serviceaccount:ops-rbac:deploy-bot"

if ! kubectl auth can-i list deployments --as="$SA" -n ops-rbac | grep -q "^yes$"; then
    echo "❌ ServiceAccount 'deploy-bot' cannot list deployments in the 'ops-rbac' namespace"
    exit 1
fi

if ! kubectl auth can-i get deployments --as="$SA" -n ops-rbac | grep -q "^yes$"; then
    echo "❌ ServiceAccount 'deploy-bot' cannot get deployments in the 'ops-rbac' namespace"
    exit 1
fi

if ! kubectl auth can-i watch replicasets --as="$SA" -n ops-rbac | grep -q "^yes$"; then
    echo "❌ ServiceAccount 'deploy-bot' cannot watch replicasets in the 'ops-rbac' namespace"
    exit 1
fi

if kubectl auth can-i list deployments --as="$SA" -n default | grep -q "^yes$"; then
    echo "❌ ServiceAccount 'deploy-bot' must not be able to list deployments in the 'default' namespace"
    exit 1
fi

echo "✅ ServiceAccount 'deploy-bot' has read-only access scoped to the 'ops-rbac' namespace"
exit 0
