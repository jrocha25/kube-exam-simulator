#!/bin/bash
set -e

FILE=/tmp/exam/q1/berthwatch.yaml

if [[ ! -s "$FILE" ]]; then
    echo "❌ $FILE does not exist or is empty"
    exit 1
fi

# kubectl create --dry-run=client renders the file alone, without the cluster.
RENDERED=$(kubectl create --dry-run=client -f "$FILE" -o json 2>/dev/null \
    | jq -s '[.[] | if .kind == "List" then .items[] else . end]' 2>/dev/null || true)
if [[ -z "$RENDERED" || "$RENDERED" == "[]" ]]; then
    echo "❌ $FILE does not contain parseable Kubernetes manifests"
    exit 1
fi

if [[ "$(echo "$RENDERED" | jq '[.[] | select(.kind == "CustomResourceDefinition")] | length')" != "0" ]]; then
    echo "❌ $FILE still contains the CustomResourceDefinition"
    exit 1
fi

DEPLOY=$(echo "$RENDERED" | jq -c '[.[] | select(.kind == "Deployment" and .metadata.name == "berthwatch")][0]')
if [[ "$DEPLOY" == "null" ]]; then
    echo "❌ $FILE does not contain the Deployment 'berthwatch' (was the release name berthwatch?)"
    exit 1
fi

IMAGE=$(echo "$DEPLOY" | jq -r '.spec.template.spec.containers[0].image')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ The rendered Deployment uses '$IMAGE'; it was not rendered from chart version 0.7.2"
    exit 1
fi

REPLICAS=$(echo "$DEPLOY" | jq -r '.spec.replicas')
if [[ "$REPLICAS" != "2" ]]; then
    echo "❌ The rendered Deployment has $REPLICAS replicas, expected 2"
    exit 1
fi

echo "✅ $FILE renders chart 0.7.2 with 2 replicas and no CRD"
exit 0
