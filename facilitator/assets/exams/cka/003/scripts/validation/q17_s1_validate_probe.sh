#!/bin/bash
set -e

NAMESPACE="ts-probe"
DEPLOYMENT="frontend"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

PROBE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '.spec.template.spec.containers[] | select(.name == "web") | .livenessProbe // {}')

HTTP_GET=$(echo "$PROBE" | jq 'has("httpGet")')
if [[ "$HTTP_GET" != "true" ]]; then
    echo "❌ Container 'web' must keep an httpGet liveness probe"
    exit 1
fi

PROBE_PATH=$(echo "$PROBE" | jq -r '.httpGet.path // ""')
if [[ "$PROBE_PATH" != "/" ]]; then
    echo "❌ Incorrect liveness probe path. Expected '/', got '$PROBE_PATH'"
    exit 1
fi

PROBE_PORT=$(echo "$PROBE" | jq -r '.httpGet.port')
if [[ "$PROBE_PORT" != "80" ]]; then
    echo "❌ Incorrect liveness probe port. Expected '80', got '$PROBE_PORT'"
    exit 1
fi

INITIAL_DELAY=$(echo "$PROBE" | jq -r '.initialDelaySeconds // ""')
if [[ "$INITIAL_DELAY" != "5" ]]; then
    echo "❌ Incorrect initialDelaySeconds. Expected '5', got '$INITIAL_DELAY'"
    exit 1
fi

PERIOD=$(echo "$PROBE" | jq -r '.periodSeconds // ""')
if [[ "$PERIOD" != "10" ]]; then
    echo "❌ Incorrect periodSeconds. Expected '10', got '$PERIOD'"
    exit 1
fi

echo "✅ The liveness probe of container 'web' performs an HTTP GET on / port 80"
exit 0
