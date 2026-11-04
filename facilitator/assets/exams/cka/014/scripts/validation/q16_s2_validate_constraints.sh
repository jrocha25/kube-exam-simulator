#!/bin/bash
set -e

NAMESPACE="customs"
DEPLOYMENT="customs-gate"

# A constraint is only worth marks once the Deployment actually runs.
if [[ "$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" != "3" ]]; then
    echo "❌ '$DEPLOYMENT' is not running 3 ready replicas"
    exit 1
fi

LABELS=$(kubectl get namespace "$NAMESPACE" -o json | jq -c '.metadata.labels')
if [[ "$(echo "$LABELS" | jq -r '.["pod-security.kubernetes.io/enforce"]')" != "restricted" ]]; then
    echo "❌ Namespace '$NAMESPACE' no longer enforces the restricted Pod Security Standard: $LABELS"
    exit 1
fi
if [[ "$(echo "$LABELS" | jq -r '.["pod-security.kubernetes.io/enforce-version"] // "latest"')" != "latest" ]]; then
    echo "❌ Namespace '$NAMESPACE' pins an older Pod Security version: $LABELS"
    exit 1
fi

CONTAINER=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq -c '.spec.template.spec.containers')
if ! echo "$CONTAINER" | jq -e 'length == 1 and .[0].name == "gate" and .[0].image == "busybox:1.36"
        and (.[0].command | join(" ") | contains("httpd -f -p 8080"))' >/dev/null; then
    echo "❌ The Deployment must keep its single container 'gate' running busybox:1.36 with its original command"
    exit 1
fi

echo "✅ The namespace still enforces restricted and the workload is unchanged apart from its security settings"
exit 0
