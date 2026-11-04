#!/bin/bash
set -e

BASE="/tmp/exam/q14/base"
NAMESPACE="kustom-fix"
OVERLAY="/tmp/exam/q14/overlays/staging"

# The base is shared with other teams: it must still declare one replica and the
# original image, and must not have acquired a namespace of its own.
REPLICAS=$(grep -E '^\s*replicas:' "$BASE/deployment.yaml" | head -1 | awk '{print $2}')
if [[ "$REPLICAS" != "1" ]]; then
    echo "❌ The base declares $REPLICAS replicas -- it was not to be edited"
    exit 1
fi
if ! grep -q "image: nginx:1.25" "$BASE/deployment.yaml"; then
    echo "❌ The base's image was changed -- it was not to be edited"
    exit 1
fi
if grep -qE '^\s*namespace:' "$BASE/kustomization.yaml"; then
    echo "❌ The base's kustomization.yaml gained a namespace -- it was not to be edited"
    exit 1
fi

# The overlay had to keep using the patch file it shipped with.
if [[ ! -f "$OVERLAY/replica-patch.yaml" ]]; then
    echo "❌ '$OVERLAY/replica-patch.yaml' is gone; the overlay had to keep using it"
    exit 1
fi
if ! grep -q "replica-patch.yaml" "$OVERLAY/kustomization.yaml"; then
    echo "❌ The overlay no longer references 'replica-patch.yaml'"
    exit 1
fi

# And it must not have been applied.
COUNT=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [[ "$COUNT" -gt 0 ]]; then
    echo "❌ Namespace '$NAMESPACE' contains $COUNT Deployment(s); the overlay was not to be applied"
    exit 1
fi

echo "✅ The base is unedited, the patch is still in use, and the overlay was not applied"
exit 0
