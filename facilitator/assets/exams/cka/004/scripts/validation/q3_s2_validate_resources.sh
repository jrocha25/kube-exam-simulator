#!/bin/bash
set -e

NAMESPACE="analytics"
DEPLOYMENT="report-builder"
CONTAINER="builder"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json \
    | jq --arg c "$CONTAINER" '.spec.template.spec.containers[] | select(.name == $c)')

if [[ -z "$SPEC" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has no container named '$CONTAINER'"
    exit 1
fi

for FIELD in "requests cpu" "requests memory" "limits cpu" "limits memory"; do
    SECTION=${FIELD% *}
    KEY=${FIELD#* }
    VALUE=$(echo "$SPEC" | jq -r --arg s "$SECTION" --arg k "$KEY" '.resources[$s][$k] // empty')
    if [[ -z "$VALUE" ]]; then
        echo "❌ Container '$CONTAINER' no longer declares resources.$SECTION.$KEY"
        exit 1
    fi
done

echo "✅ Container '$CONTAINER' still declares CPU and memory requests and limits"
exit 0
