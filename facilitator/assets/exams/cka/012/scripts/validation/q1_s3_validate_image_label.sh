#!/bin/bash
set -e

# Exits non-zero when the mirror Pod is absent rather than skipping: "the image
# and label are right" must never be true of a Pod that does not exist.

NAMESPACE="node-sensor"
POD_BASE="sensor-collector"
ALIAS="node02"
CONTAINER="collector"
IMAGE="nginx:1.27.4"
LABEL_KEY="duty"
LABEL_VALUE="telemetry"

NODE=$(awk -F= -v a="$ALIAS" '$1==a {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1)
if [[ -z "$NODE" ]]; then
    NODE=$(kubectl get nodes -l "ck-x.io/alias=${ALIAS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [[ -z "$NODE" ]]; then
    echo "❌ No node carries the label ck-x.io/alias=${ALIAS}"
    exit 1
fi

POD="${POD_BASE}-${NODE}"
JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ No mirror Pod '${POD}' in namespace '${NAMESPACE}'"
    exit 1
fi

COUNT=$(jq '.spec.containers | length' <<<"$JSON")
NAME=$(jq -r '.spec.containers[0].name // empty' <<<"$JSON")
IMG=$(jq -r '.spec.containers[0].image // empty' <<<"$JSON")
if [[ "$COUNT" != "1" || "$NAME" != "$CONTAINER" || "$IMG" != "$IMAGE" ]]; then
    echo "❌ '${POD}' must have exactly one container named '${CONTAINER}' running '${IMAGE}'"
    echo "   Found ${COUNT} container(s), '${NAME:-none}' running '${IMG:-none}'"
    exit 1
fi

GOT=$(jq -r --arg k "$LABEL_KEY" '.metadata.labels[$k] // empty' <<<"$JSON")
if [[ "$GOT" != "$LABEL_VALUE" ]]; then
    echo "❌ '${POD}' carries ${LABEL_KEY}='${GOT:-unset}', expected '${LABEL_VALUE}'"
    exit 1
fi

echo "✅ '${POD}' runs '${IMAGE}' in container '${CONTAINER}' and carries ${LABEL_KEY}=${LABEL_VALUE}"
exit 0
