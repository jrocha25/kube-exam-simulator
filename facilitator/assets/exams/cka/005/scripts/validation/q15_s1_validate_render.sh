#!/bin/bash
set -e

OVERLAY="/tmp/exam/q15/overlays/staging"
FILE="/tmp/exam/q15/rendered.yaml"

OUTPUT=$(kubectl kustomize "$OVERLAY" 2>&1) || {
    echo "❌ 'kubectl kustomize $OVERLAY' still fails:"
    echo "$OUTPUT"
    exit 1
}

if [[ -z "$OUTPUT" ]]; then
    echo "❌ '$OVERLAY' rendered nothing"
    exit 1
fi

if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' does not exist or is empty"
    exit 1
fi

KUSTOMIZATION="$OVERLAY/kustomization.yaml"
for patch in replicas-patch.yaml image-patch.yaml; do
    if ! grep -q "$patch" "$KUSTOMIZATION"; then
        echo "❌ The overlay no longer uses '$patch'"
        exit 1
    fi
    if [[ ! -f "$OVERLAY/$patch" ]]; then
        echo "❌ '$patch' no longer exists in the overlay"
        exit 1
    fi
done

echo "✅ '$OVERLAY' renders cleanly and still uses both patch files"
exit 0
