#!/bin/bash

set -e

# The silent fault. A strategic merge patch names containers by their "name" key,
# so the seeded patch (which says "check" where the base says "checker") appends
# a SECOND container instead of editing the first. The build succeeds and the
# rendered Deployment is simply wrong.
#
# Asserting the container count is therefore the whole point: an image check
# alone would pass against the broken output, because the appended container does
# carry the approved image.

NAMESPACE="kustom-repair"
DEPLOYMENT="customs-check"
CONTAINER="checker"
IMAGE="nginx:1.27.4"
REPLICAS="4"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

COUNT=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json \
    | jq '.spec.template.spec.containers | length')
if [[ "$COUNT" != "1" ]]; then
    echo "❌ '$DEPLOYMENT' has $COUNT containers, expected exactly 1"
    exit 1
fi

NAME=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].name}')
if [[ "$NAME" != "$CONTAINER" ]]; then
    echo "❌ The container is named '$NAME', expected '$CONTAINER'"
    exit 1
fi

ACTUAL_IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$ACTUAL_IMAGE" != "$IMAGE" ]]; then
    echo "❌ The container runs '$ACTUAL_IMAGE', expected '$IMAGE'"
    exit 1
fi

DECLARED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$DECLARED" != "$REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' declares ${DECLARED:-no} replicas, expected $REPLICAS"
    exit 1
fi

CM=$(kubectl get configmap -n "$NAMESPACE" -o json \
    | jq -r '[ .items[] | select(.metadata.name | startswith("checker-settings")) | select(.data.MODE == "strict") ] | length')
if [[ "$CM" -lt 1 ]]; then
    echo "❌ No generated ConfigMap named 'checker-settings...' with MODE=strict in '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
    [[ "$READY" == "$REPLICAS" ]] && break
    sleep 5
done

if [[ "$READY" != "$REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' has ${READY:-0}/${REPLICAS} ready replicas"
    exit 1
fi

echo "✅ '$DEPLOYMENT' runs $REPLICAS ready replicas of a single '$CONTAINER' container on '$IMAGE'"
exit 0
