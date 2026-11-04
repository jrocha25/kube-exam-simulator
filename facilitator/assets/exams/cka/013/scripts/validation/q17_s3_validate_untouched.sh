#!/bin/bash
set -e

NAMESPACE="ts-lighthouse"
POD="beacon-core"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' no longer exists"
    exit 1
fi

# A constraint: true of an untouched Pod, so it only counts once the debugging
# the question asks for has happened.
if [[ "$(echo "$JSON" | jq '[.spec.ephemeralContainers[]? | select(.targetContainerName == "core")] | length')" == "0" ]]; then
    echo "❌ No ephemeral container targeting 'core' was attached"
    exit 1
fi

if [[ "$(echo "$JSON" | jq -r '.metadata.uid')" != "$(cat /tmp/exam/q17/.pod.uid 2>/dev/null)" ]]; then
    echo "❌ '$POD' was recreated"
    exit 1
fi
CORE=$(echo "$JSON" | jq -c '.status.containerStatuses[]? | select(.name == "core") | {restartCount, running: (.state.running != null)}')
if [[ "$CORE" != '{"restartCount":0,"running":true}' ]]; then
    echo "❌ The container 'core' was restarted or is not running ($CORE)"
    exit 1
fi

echo "✅ '$POD' and its container 'core' were never restarted"
exit 0
