#!/bin/bash

set -e

# The form check. The question asks for ONE patch entry selected by label, and
# the live result alone cannot distinguish that from two patches written by name.
#
# Rather than trying to count YAML entries with grep, this asserts the thing that
# a by-name answer cannot avoid: writing the Deployment names down. A
# label-selected patch never mentions them.

OVERLAY="/tmp/exam/q3/overlays/prod"

if [[ ! -d "$OVERLAY" ]]; then
    echo "❌ Overlay directory '$OVERLAY' does not exist"
    exit 1
fi

if ! grep -rqs "labelSelector" "$OVERLAY"; then
    echo "❌ No 'labelSelector' in '$OVERLAY'; the patch must select its targets by label"
    exit 1
fi

for NAME in route-planner dispatch-worker; do
    if grep -rqs -- "$NAME" "$OVERLAY"; then
        echo "❌ '$NAME' is named in '$OVERLAY'; the patch must select by label, not by name"
        exit 1
    fi
done

echo "✅ The overlay patches its targets through a labelSelector, naming neither backend"
exit 0
