#!/bin/bash
set -e

NAMESPACE="config-rotate"
NEW="feature-flags-v2"
OLD="feature-flags"

JSON=$(kubectl get configmap "$NEW" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ ConfigMap '$NEW' not found in namespace '$NAMESPACE'"
    exit 1
fi

CHANNEL=$(echo "$JSON" | jq -r '.data.RELEASE_CHANNEL // empty')
BATCH=$(echo "$JSON" | jq -r '.data.MAX_BATCH_SIZE // empty')

if [[ "$CHANNEL" != "stable" ]]; then
    echo "❌ '$NEW' has RELEASE_CHANNEL='${CHANNEL:-<missing>}', expected 'stable'"
    exit 1
fi
if [[ "$BATCH" != "200" ]]; then
    echo "❌ '$NEW' has MAX_BATCH_SIZE='${BATCH:-<missing>}', expected '200'"
    exit 1
fi

IMMUTABLE=$(echo "$JSON" | jq -r '.immutable // false')
if [[ "$IMMUTABLE" != "true" ]]; then
    echo "❌ '$NEW' is not marked immutable"
    exit 1
fi

if kubectl patch configmap "$NEW" -n "$NAMESPACE" \
        -p '{"data":{"RELEASE_CHANNEL":"beta"}}' >/dev/null 2>&1; then
    echo "❌ '$NEW' accepted an update to its data -- it is not really immutable"
    exit 1
fi

# The original had to be left alone. Deleting it or editing it in place is the
# route the question is steering away from.
OLD_JSON=$(kubectl get configmap "$OLD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$OLD_JSON" ]]; then
    echo "❌ The original ConfigMap '$OLD' is gone; it had to be left in place"
    exit 1
fi

OLD_CHANNEL=$(echo "$OLD_JSON" | jq -r '.data.RELEASE_CHANNEL // empty')
if [[ "$OLD_CHANNEL" != "beta" ]]; then
    echo "❌ '$OLD' now has RELEASE_CHANNEL='${OLD_CHANNEL:-<missing>}'; it had to stay unchanged"
    exit 1
fi

echo "✅ '$NEW' is immutable with the new values, and '$OLD' is untouched"
exit 0
