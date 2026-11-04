#!/bin/bash

set -e

# Deleting the offending patch file is a repair that satisfies the end state
# without diagnosing anything. The question forbids it and this is what enforces
# it: both files must still exist and still be referenced.
#
# Guarded on the overlay actually building. Both files are present and referenced
# in the broken state the question starts from, so without this guard the check
# would hand out marks for doing nothing at all.

OVERLAY="/tmp/exam/q5/overlays/staging"
KUSTOMIZATION="$OVERLAY/kustomization.yaml"

if [[ ! -f "$KUSTOMIZATION" ]]; then
    echo "❌ '$KUSTOMIZATION' is missing"
    exit 1
fi

if ! kubectl kustomize "$OVERLAY" &> /dev/null; then
    echo "❌ The overlay still does not build, so keeping its files proves nothing yet"
    exit 1
fi

for FILE in container-patch.yaml replica-patch.yaml; do
    if [[ ! -f "$OVERLAY/$FILE" ]]; then
        echo "❌ '$OVERLAY/$FILE' no longer exists; the overlay must keep using it"
        exit 1
    fi
    if ! grep -qs -- "$FILE" "$KUSTOMIZATION"; then
        echo "❌ '$FILE' is no longer referenced from '$KUSTOMIZATION'"
        exit 1
    fi
done

echo "✅ Both patch files still exist and are still referenced by the overlay"
exit 0
