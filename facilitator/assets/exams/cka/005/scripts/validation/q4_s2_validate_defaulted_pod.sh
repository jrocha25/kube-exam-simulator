#!/bin/bash
set -e

NAMESPACE="registry-audit"
POD="search-api"
CONTAINER="api"
EXPECTED_IMAGE="nginx:1.27.4"
EXPECTED_LIMIT="256Mi"
EXPECTED_REQUEST="128Mi"

if ! kubectl get pod "$POD" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

IMAGE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath="{.spec.containers[?(@.name=='$CONTAINER')].image}")
if [[ "$IMAGE" != "$EXPECTED_IMAGE" ]]; then
    echo "❌ Container '$CONTAINER' runs '${IMAGE:-<none>}', expected '$EXPECTED_IMAGE'"
    exit 1
fi

LIMIT=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath="{.spec.containers[?(@.name=='$CONTAINER')].resources.limits.memory}")
if [[ "$LIMIT" != "$EXPECTED_LIMIT" ]]; then
    echo "❌ Container '$CONTAINER' has memory limit '${LIMIT:-<unset>}', expected '$EXPECTED_LIMIT'"
    exit 1
fi

# A hand written limit with no request would default the request to the limit.
# A request of 128Mi is only produced by the LimitRange's defaultRequest.
REQUEST=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath="{.spec.containers[?(@.name=='$CONTAINER')].resources.requests.memory}")
if [[ "$REQUEST" != "$EXPECTED_REQUEST" ]]; then
    echo "❌ Container '$CONTAINER' has memory request '${REQUEST:-<unset>}', expected '$EXPECTED_REQUEST' applied by the LimitRange"
    exit 1
fi

for _ in $(seq 1 12); do
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
done

if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is in phase '${PHASE:-<unknown>}', expected 'Running'"
    exit 1
fi

echo "✅ Pod '$POD' is Running with the memory limit $EXPECTED_LIMIT applied by the LimitRange"
exit 0
