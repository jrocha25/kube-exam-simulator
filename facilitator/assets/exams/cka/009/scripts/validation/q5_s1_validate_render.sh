#!/bin/bash

set -e

# The loud fault: while the configMapGenerator still says "behavior: merge" for a
# ConfigMap no base declares, kustomize refuses to build at all.

OVERLAY="/tmp/exam/q5/overlays/staging"

if [[ ! -d "$OVERLAY" ]]; then
    echo "❌ Overlay directory '$OVERLAY' does not exist"
    exit 1
fi

if ! OUTPUT=$(kubectl kustomize "$OVERLAY" 2>&1); then
    echo "❌ 'kubectl kustomize $OVERLAY' still fails:"
    echo "$OUTPUT" | head -n 5
    exit 1
fi

if [[ -z "$OUTPUT" ]]; then
    echo "❌ 'kubectl kustomize $OVERLAY' produced no output"
    exit 1
fi

echo "✅ The overlay at '$OVERLAY' builds successfully"
exit 0
