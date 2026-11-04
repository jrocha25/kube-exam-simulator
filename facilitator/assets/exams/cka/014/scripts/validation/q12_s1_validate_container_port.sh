#!/bin/bash
set -e

NAMESPACE="tally"
DEPLOYMENT="tally-board"

PORTS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -c '[.spec.template.spec.containers[] | select(.name == "board") | .ports[]?]' || true)
if [[ -z "$PORTS" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' or its container 'board' not found"
    exit 1
fi

if ! echo "$PORTS" | jq -e 'any(.[]; .name == "http" and .containerPort == 80 and ((.protocol // "TCP") == "TCP"))' >/dev/null; then
    echo "❌ Container 'board' does not declare port 80/TCP named http: $PORTS"
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
if [[ "$READY" != "2" ]]; then
    echo "❌ '$DEPLOYMENT' does not have 2 ready replicas"
    exit 1
fi

echo "✅ Container 'board' declares port 80 as http and 2 replicas are ready"
exit 0
