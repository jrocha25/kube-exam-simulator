#!/bin/bash
set -e

NAMESPACE="ts-lighthouse"
POD="beacon-core"

TARGETS=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r '[.spec.ephemeralContainers[]? | select(.targetContainerName == "core")] | length' || true)
if [[ -z "$TARGETS" || "$TARGETS" == "0" ]]; then
    echo "❌ No ephemeral container targeting 'core' was attached to '$POD'"
    exit 1
fi

echo "✅ An ephemeral container targeting 'core' was attached to '$POD'"
exit 0
