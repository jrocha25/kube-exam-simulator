#!/bin/bash
set -e

NAMESPACE="config-rotate"
DEPLOYMENT="feature-api"
NEW="feature-flags-v2"
EXPECTED_REPLICAS=2

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(echo "$JSON" | jq -r '.spec.replicas')
if [[ "$SPEC" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' declares $SPEC replicas, expected $EXPECTED_REPLICAS"
    exit 1
fi

READY=$(echo "$JSON" | jq -r '.status.readyReplicas // 0')
if [[ "$READY" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' has $READY/$EXPECTED_REPLICAS ready replicas"
    exit 1
fi

REF=$(echo "$JSON" | jq -r '[.spec.template.spec.containers[0].envFrom[]?.configMapRef.name] | join(",")')
if [[ "$REF" != "$NEW" ]]; then
    echo "❌ The container reads envFrom '${REF:-<nothing>}', expected a configMapRef to '$NEW'"
    exit 1
fi

# The environment of a *running* Pod, not of the ConfigMap: repointing the
# Deployment without letting the new Pods roll out leaves the old environment in
# place, because envFrom is resolved when a container starts.
PODS=$(kubectl get pods -n "$NAMESPACE" -l app=feature-api \
    -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}')
if [[ -z "$PODS" ]]; then
    echo "❌ No Running '$DEPLOYMENT' Pods found"
    exit 1
fi

while IFS= read -r pod; do
    [[ -z "$pod" ]] && continue
    # A Pod that is on its way out still reports phase Running; skip it rather
    # than failing the candidate for a Pod Kubernetes is already deleting.
    if [[ -n "$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null)" ]]; then
        continue
    fi
    ENVOUT=$(kubectl exec -n "$NAMESPACE" "$pod" -- env 2>/dev/null || true)
    if ! grep -q '^RELEASE_CHANNEL=stable$' <<<"$ENVOUT"; then
        GOT=$(grep '^RELEASE_CHANNEL=' <<<"$ENVOUT" || echo "RELEASE_CHANNEL=<unset>")
        echo "❌ Pod '$pod' has $GOT, expected RELEASE_CHANNEL=stable."
        echo "   envFrom is resolved when the container starts, so the Pods have to be replaced."
        exit 1
    fi
    if ! grep -q '^MAX_BATCH_SIZE=200$' <<<"$ENVOUT"; then
        GOT=$(grep '^MAX_BATCH_SIZE=' <<<"$ENVOUT" || echo "MAX_BATCH_SIZE=<unset>")
        echo "❌ Pod '$pod' has $GOT, expected MAX_BATCH_SIZE=200"
        exit 1
    fi
done <<<"$PODS"

echo "✅ Every running Pod reads '$NEW' through envFrom and carries the new environment"
exit 0
